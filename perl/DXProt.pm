#!/usr/bin/perl
#
# This module impliments the protocal mode for a dx cluster
#
# Copyright (c) 1998 Dirk Koopman G1TLH
#
# $Id$
# 

package DXProt;

@ISA = qw(DXChannel);

use DXUtil;
use DXChannel;
use DXUser;
use DXM;
use DXProtVars;
use DXCommandmode;
use DXLog;
use Spot;
use DXProtout;
use DXDebug;
use Filter;
use Local;
use DXDb;
use AnnTalk;
use Geomag;
use WCY;
use Time::HiRes qw(gettimeofday tv_interval);
use BadWords;
use DXHash;
use Route;
use Route::Node;
use Script;

use strict;

use vars qw($VERSION $BRANCH);
$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /\d+\.\d+\.(\d+)\.(\d+)/ ) || 0;
$main::build += $VERSION;
$main::branch += $BRANCH;

use vars qw($pc11_max_age $pc23_max_age $last_pc50 $eph_restime $eph_info_restime $eph_pc34_restime
			$last_hour $last10 %eph  %pings %rcmds $ann_to_talk
			%nodehops $baddx $badspotter $badnode $censorpc $rspfcheck
			$allowzero $decode_dk0wcy $send_opernam @checklist);

$pc11_max_age = 1*3600;			# the maximum age for an incoming 'real-time' pc11
$pc23_max_age = 1*3600;			# the maximum age for an incoming 'real-time' pc23

$last_hour = time;				# last time I did an hourly periodic update
%pings = ();                    # outstanding ping requests outbound
%rcmds = ();                    # outstanding rcmd requests outbound
%nodehops = ();                 # node specific hop control
$censorpc = 1;					# Do a BadWords::check on text fields and reject things
								# loads of 'bad things'
$baddx = new DXHash "baddx";
$badspotter = new DXHash "badspotter";
$badnode = new DXHash "badnode";
$last10 = $last_pc50 = time;
$ann_to_talk = 1;
$rspfcheck = 1;
$eph_restime = 180;
$eph_info_restime = 60*60;
$eph_pc34_restime = 30;

@checklist = 
(
 [ qw(c c m bp bc c) ],			# pc10
 [ qw(f m d t m c c h) ],		# pc11
 [ qw(c bc m bp bm p h) ],		# pc12
 [ qw(c h) ],					# 
 [ qw(c h) ],					# 
 [ qw(c m h) ],					# 
 undef ,						# pc16 has to be validated manually
 [ qw(c c h) ],					# pc17
 [ qw(m n) ],					# pc18
 undef ,						# pc19 has to be validated manually
 undef ,						# pc20 no validation
 [ qw(c m h) ],					# pc21
 undef ,						# pc22 no validation
 [ qw(d n n n n m c c h) ],		# pc23
 [ qw(c p h) ],					# pc24
 [ qw(c c n n) ],				# pc25
 [ qw(f m d t m c c bc) ],		# pc26
 [ qw(d n n n n m c c bc) ],	# pc27
 [ qw(c c m c d t p m bp n p bp bc) ], # pc28
 [ qw(c c n m) ],				# pc29
 [ qw(c c n) ],					# pc30
 [ qw(c c n) ],					# pc31
 [ qw(c c n) ],					# pc32
 [ qw(c c n) ],					# pc33
 [ qw(c c m) ],					# pc34
 [ qw(c c m) ],					# pc35
 [ qw(c c m) ],					# pc36
 [ qw(c c n m) ],				# pc37
 undef,							# pc38 not interested
 [ qw(c m) ],					# pc39
 [ qw(c c m p n) ],				# pc40
 [ qw(c n m h) ],				# pc41
 [ qw(c c n) ],					# pc42
 undef,							# pc43 don't handle it
 [ qw(c c n m m c) ],			# pc44
 [ qw(c c n m) ],				# pc45
 [ qw(c c n) ],					# pc46
 undef,							# pc47
 undef,							# pc48
 [ qw(c m h) ],					# pc49
 [ qw(c n h) ],					# pc50
 [ qw(c c n) ],					# pc51
 undef,
 undef,
 undef,
 undef,
 undef,
 undef,
 undef,
 undef,
 undef,							# pc60
 undef,
 undef,
 undef,
 undef,
 undef,
 undef,
 undef,
 undef,
 undef,
 undef,							# pc70
 undef,
 undef,
 [ qw(d n n n n n n m m m c c h) ],	# pc73
 undef,
 undef,
 undef,
 undef,
 undef,
 undef,
 undef,							# pc80
 undef,
 undef,
 undef,
 [ qw(c c c m) ],				# pc84
 [ qw(c c c m) ],				# pc85
);

# use the entry in the check list to check the field list presented
# return OK if line NOT in check list (for now)
sub check
{
	my $n = shift;
	$n -= 10;
	return 0 if $n < 0 || $n > @checklist; 
	my $ref = $checklist[$n];
	return 0 unless ref $ref;
	
	my $i;
	shift;    # not interested in the first field
	for ($i = 0; $i < @$ref; $i++) {
		my ($blank, $act) = $$ref[$i] =~ /^(b?)(\w)$/;
		return 0 unless $act;
		next if $blank && $_[$i] =~ /^[ \*]$/;
		if ($act eq 'c') {
			return $i+1 unless is_callsign($_[$i]);
		} elsif ($act eq 'm') {
			return $i+1 unless is_pctext($_[$i]);
		} elsif ($act eq 'p') {
			return $i+1 unless is_pcflag($_[$i]);
		} elsif ($act eq 'f') {
			return $i+1 unless is_freq($_[$i]);
		} elsif ($act eq 'n') {
			return $i+1 unless $_[$i] =~ /^[\d ]+$/;
		} elsif ($act eq 'h') {
			return $i+1 unless $_[$i] =~ /^H\d\d?$/;
		} elsif ($act eq 'd') {
			return $i+1 unless $_[$i] =~ /^\s*\d+-\w\w\w-[12][90]\d\d$/;
		} elsif ($act eq 't') {
			return $i+1 unless $_[$i] =~ /^[012]\d[012345]\dZ$/;
		}
	}
	return 0;
}

sub init
{
	my $user = DXUser->get($main::mycall);
	$DXProt::myprot_version += $main::version*100;
	$main::me = DXProt->new($main::mycall, 0, $user); 
	$main::me->{here} = 1;
	$main::me->{state} = "indifferent";
	do "$main::data/hop_table.pl" if -e "$main::data/hop_table.pl";
	confess $@ if $@;
	$main::me->{sort} = 'S';    # S for spider
	$main::me->{priv} = 9;
	$main::me->{metric} = 0;
	$main::me->{pingave} = 0;
	
#	$Route::Node::me->adddxchan($main::me);
}

#
# obtain a new connection this is derived from dxchannel
#

sub new 
{
	my $self = DXChannel::alloc(@_);

	# add this node to the table, the values get filled in later
	my $pkg = shift;
	my $call = shift;
	$main::routeroot->add($call, '5000', Route::here(1)) if $call ne $main::mycall;

	return $self;
}

# this is how a pc connection starts (for an incoming connection)
# issue a PC38 followed by a PC18, then wait for a PC20 (remembering
# all the crap that comes between).
sub start
{
	my ($self, $line, $sort) = @_;
	my $call = $self->{call};
	my $user = $self->{user};

	# log it
	my $host = $self->{conn}->{peerhost} || "unknown";
	Log('DXProt', "$call connected from $host");
	
	# remember type of connection
	$self->{consort} = $line;
	$self->{outbound} = $sort eq 'O';
	my $priv = $user->priv;
	$priv = $user->priv(1) unless $priv;
	$self->{priv} = $priv;     # other clusters can always be 'normal' users
	$self->{lang} = $user->lang || 'en';
	$self->{isolate} = $user->{isolate};
	$self->{consort} = $line;	# save the connection type
	$self->{here} = 1;
	$self->{width} = 80;

	# sort out registration
	$self->{registered} = 1;

	# get the output filters
	$self->{spotsfilter} = Filter::read_in('spots', $call, 0) || Filter::read_in('spots', 'node_default', 0);
	$self->{wwvfilter} = Filter::read_in('wwv', $call, 0) || Filter::read_in('wwv', 'node_default', 0);
	$self->{wcyfilter} = Filter::read_in('wcy', $call, 0) || Filter::read_in('wcy', 'node_default', 0);
	$self->{annfilter} = Filter::read_in('ann', $call, 0) || Filter::read_in('ann', 'node_default', 0) ;
	$self->{routefilter} = Filter::read_in('route', $call, 0) || Filter::read_in('route', 'node_default', 0) unless $self->{isolate} ;


	# get the INPUT filters (these only pertain to Clusters)
	$self->{inspotsfilter} = Filter::read_in('spots', $call, 1) || Filter::read_in('spots', 'node_default', 1);
	$self->{inwwvfilter} = Filter::read_in('wwv', $call, 1) || Filter::read_in('wwv', 'node_default', 1);
	$self->{inwcyfilter} = Filter::read_in('wcy', $call, 1) || Filter::read_in('wcy', 'node_default', 1);
	$self->{inannfilter} = Filter::read_in('ann', $call, 1) || Filter::read_in('ann', 'node_default', 1);
	$self->{inroutefilter} = Filter::read_in('route', $call, 1) || Filter::read_in('route', 'node_default', 1) unless $self->{isolate};
	
	# set unbuffered and no echo
	$self->send_now('B',"0");
	$self->send_now('E',"0");
	$self->conn->echo(0) if $self->conn->can('echo');
	
	# ping neighbour node stuff
	my $ping = $user->pingint;
	$ping = 5*60 unless defined $ping;
	$self->{pingint} = $ping;
	$self->{nopings} = $user->nopings || 2;
	$self->{pingtime} = [ ];
	$self->{pingave} = 999;
	$self->{metric} ||= 100;
	$self->{lastping} = $main::systime;

	# send initialisation string
	unless ($self->{outbound}) {
		$self->send(pc18());
	}
	
	$self->state('init');
	$self->{pc50_t} = $main::systime;

	# send info to all logged in thingies
	$self->tell_login('loginn');

	# run a script send the output to the debug file
	my $script = new Script(lc $call) || new Script('node_default');
	$script->run($self) if $script;
}

#
# This is the normal pcxx despatcher
#
sub normal
{
	my ($self, $line) = @_;
	my @field = split /\^/, $line;
	return unless @field;
	
	pop @field if $field[-1] eq '~';
	
#	print join(',', @field), "\n";
						
	
	# process PC frames, this will fail unless the frame starts PCnn
	my ($pcno) = $field[0] =~ /^PC(\d\d)/; # just get the number
	return unless $pcno;
	return if $pcno < 10 || $pcno > 99;

	# check for and dump bad protocol messages
	my $n = check($pcno, @field);
	if ($n) {
		dbg("PCPROT: bad field $n, dumped (" . parray($checklist[$pcno-10]) . ")") if isdbg('chanerr');
		return;
	}

	# local processing 1
	my $pcr;
	eval {
		$pcr = Local::pcprot($self, $pcno, @field);
	};
#	dbg("Local::pcprot error $@") if isdbg('local') if $@;
	return if $pcr;
	
 SWITCH: {
		if ($pcno == 10) {		# incoming talk

			# rsfp check
			return if $rspfcheck and !$self->rspfcheck(0, $field[6], $field[1]);
			
			# will we allow it at all?
			if ($censorpc) {
				my @bad;
				if (@bad = BadWords::check($field[3])) {
					dbg("PCPROT: Bad words: @bad, dropped") if isdbg('chanerr');
					return;
				}
			}

			# is it for me or one of mine?
			my ($from, $to, $via, $call, $dxchan);
			$from = $field[1];
			if ($field[5] gt ' ') {
				$via = $field[2];
				$to = $field[5];
			} else {
				$to = $field[2];
			}

			# if we are converting announces to talk is it a dup?
			if ($ann_to_talk) {
				if (AnnTalk::is_talk_candidate($from, $field[3]) && AnnTalk::dup($from, $to, $field[3])) {
					dbg("DXPROT: Dupe talk from announce, dropped") if isdbg('chanerr');
					return;
				}
			}

			# it is here and logged on
			$dxchan = DXChannel->get($main::myalias) if $to eq $main::mycall;
			$dxchan = DXChannel->get($to) unless $dxchan;
			if ($dxchan && $dxchan->is_user) {
				$field[3] =~ s/\%5E/^/g;
				$dxchan->talk($from, $to, $via, $field[3]);
				return;
			}

			# is it elsewhere, visible on the cluster via the to address?
			# note: this discards the via unless the to address is on
			# the via address
			my ($ref, $vref);
			if ($ref = Route::get($to)) {
				$vref = Route::Node::get($via) if $via;
				$vref = undef unless $vref && grep $to eq $_, $vref->users;
				$ref->dxchan->talk($from, $to, $vref ? $via : undef, $field[3], $field[6]);
				return;
			}

			# not visible here, send a message of condolence
			$vref = undef;
			$ref = Route::get($from);
			$vref = $ref = Route::Node::get($field[6]) unless $ref; 
			if ($ref) {
				$dxchan = $ref->dxchan;
				$dxchan->talk($main::mycall, $from, $vref ? $vref->call : undef, $dxchan->msg('talknh', $to) );
			}
			return;
		}
		
		if ($pcno == 11 || $pcno == 26) { # dx spot

			# route 'foreign' pc26s 
			if ($pcno == 26) {
				if ($field[7] ne $main::mycall) {
					$self->route($field[7], $line);
					return;
				}
			}
			
			# rsfp check
#			return if $rspfcheck and !$self->rspfcheck(1, $field[7], $field[6]);

			# if this is a 'nodx' node then ignore it
			if ($badnode->in($field[7])) {
				dbg("PCPROT: Bad Node, dropped") if isdbg('chanerr');
				return;
			}
			
			# if this is a 'bad spotter' user then ignore it
			if ($badspotter->in($field[6])) {
				dbg("PCPROT: Bad Spotter, dropped") if isdbg('chanerr');
				return;
			}
			
			# convert the date to a unix date
			my $d = cltounix($field[3], $field[4]);
			# bang out (and don't pass on) if date is invalid or the spot is too old (or too young)
			if (!$d || ($pcno == 11 && ($d < $main::systime - $pc11_max_age || $d > $main::systime + 900))) {
				dbg("PCPROT: Spot ignored, invalid date or out of range ($field[3] $field[4])\n") if isdbg('chanerr');
				return;
			}

			# is it 'baddx'
			if ($baddx->in($field[2]) || BadWords::check($field[2]) || $field[2] =~ /COCK/) {
				dbg("PCPROT: Bad DX spot, ignored") if isdbg('chanerr');
				return;
			}
			
			# do some de-duping
			$field[5] =~ s/^\s+//;      # take any leading blanks off
			$field[2] = unpad($field[2]);	# take off leading and trailing blanks from spotted callsign
			if ($field[2] =~ /BUST\w*$/) {
				dbg("PCPROT: useless 'BUSTED' spot") if isdbg('chanerr');
				return;
			}
			if ($censorpc) {
				my @bad;
				if (@bad = BadWords::check($field[5])) {
					dbg("PCPROT: Bad words: @bad, dropped") if isdbg('chanerr');
					return;
				}
			}


			my @spot = Spot::prepare($field[1], $field[2], $d, $field[5], $field[6], $field[7]);
			# global spot filtering on INPUT
			if ($self->{inspotsfilter}) {
				my ($filter, $hops) = $self->{inspotsfilter}->it(@spot);
				unless ($filter) {
					dbg("PCPROT: Rejected by input spot filter") if isdbg('chanerr');
					return;
				}
			}

			# this goes after the input filtering, but before the add
			# so that if it is input filtered, it isn't added to the dup
			# list. This allows it to come in from a "legitimate" source
			if (Spot::dup($field[1], $field[2], $d, $field[5])) {
				dbg("PCPROT: Duplicate Spot ignored\n") if isdbg('chanerr');
				return;
			}

			# add it 
			Spot::add(@spot);

            #
			# @spot at this point contains:-
            # freq, spotted call, time, text, spotter, spotted cc, spotters cc, orig node
			# then  spotted itu, spotted cq, spotters itu, spotters cq
			# you should be able to route on any of these
            #
			
			# fix up qra locators of known users 
			my $user = DXUser->get_current($spot[4]);
			if ($user) {
				my $qra = $user->qra;
				unless ($qra && is_qra($qra)) {
					my $lat = $user->lat;
					my $long = $user->long;
					if (defined $lat && defined $long) {
						$user->qra(DXBearing::lltoqra($lat, $long)); 
						$user->put;
					}
				}

				# send a remote command to a distant cluster if it is visible and there is no
				# qra locator and we havn't done it for a month.

				unless ($user->qra) {
					my $node;
					my $to = $user->homenode;
					my $last = $user->lastoper || 0;
					if ($send_opernam && $to && $to ne $main::mycall && $main::systime > $last + $DXUser::lastoperinterval && ($node = Route::Node::get($to)) ) {
						my $cmd = "forward/opernam $spot[4]";
						# send the rcmd but we aren't interested in the replies...
						my $dxchan = $node->dxchan;
						if ($dxchan && $dxchan->is_clx) {
							route(undef, $to, pc84($main::mycall, $to, $main::mycall, $cmd));
						} else {
							route(undef, $to, pc34($main::mycall, $to, $cmd));
						}
						if ($to ne $field[7]) {
							$to = $field[7];
							$node = Route::Node::get($to);
							if ($node) {
								$dxchan = $node->dxchan;
								if ($dxchan && $dxchan->is_clx) {
									route(undef, $to, pc84($main::mycall, $to, $main::mycall, $cmd));
								} else {
									route(undef, $to, pc34($main::mycall, $to, $cmd));
								}
							}
						}
						$user->lastoper($main::systime);
						$user->put;
					}
				}
			}
				
			# local processing 
			my $r;
			eval {
				$r = Local::spot($self, @spot);
			};
#			dbg("Local::spot1 error $@") if isdbg('local') if $@;
			return if $r;

			# DON'T be silly and send on PC26s!
			return if $pcno == 26;

			# send out the filtered spots
			send_dx_spot($self, $line, @spot) if @spot;
			return;
		}
		
		if ($pcno == 12) {		# announces

#			return if $rspfcheck and !$self->rspfcheck(1, $field[5], $field[1]);

			# announce duplicate checking
			$field[3] =~ s/^\s+//;  # remove leading blanks

			if ($censorpc) {
				my @bad;
				if (@bad = BadWords::check($field[3])) {
					dbg("PCPROT: Bad words: @bad, dropped") if isdbg('chanerr');
					return;
				}
			}

			if ($field[2] eq '*' || $field[2] eq $main::mycall) {


				# here's a bit of fun, convert incoming ann with a callsign in the first word
				# or one saying 'to <call>' to a talk if we can route to the recipient
				if ($ann_to_talk) {
					my $call = AnnTalk::is_talk_candidate($field[1], $field[3]);
					if ($call) {
						my $ref = Route::get($call);
						if ($ref) {
							my $dxchan = $ref->dxchan;
							$dxchan->talk($field[1], $call, undef, $field[3], $field[5]) if $dxchan != $self;
							return;
						}
					}
				}
	
				# send it
				$self->send_announce($line, @field[1..6]);
			} else {
				$self->route($field[2], $line);
			}
			return;
		}
		
		if ($pcno == 13) {
			last SWITCH;
		}
		if ($pcno == 14) {
			last SWITCH;
		}
		if ($pcno == 15) {
			last SWITCH;
		}
		
		if ($pcno == 16) {		# add a user

			if (eph_dup($line)) {
				dbg("PCPROT: dup PC16 detected") if isdbg('chanerr');
				return;
			}

			# general checks
			my $dxchan;
			my $ncall = $field[1];
			my $newline = "PC16^";
			
			if ($ncall eq $main::mycall) {
				dbg("PCPROT: trying to alter config on this node from outside!") if isdbg('chanerr');
				return;
			}
			my $parent = Route::Node::get($ncall); 
			unless ($parent) {
				dbg("PCPROT: Node $ncall not in config") if isdbg('chanerr');
				return;
			}
			$dxchan = $parent->dxchan;
			if ($dxchan && $dxchan ne $self) {
				dbg("PCPROT: PC16 from $self->{call} trying to alter locally connected $ncall, ignored!") if isdbg('chanerr');
				return;
			}

			# input filter if required
			return unless $self->in_filter_route($parent);
			
			my $i;
			my @rout;
			for ($i = 2; $i < $#field; $i++) {
				my ($call, $conf, $here) = $field[$i] =~ /^(\S+) (\S) (\d)/o;
				next unless $call && $conf && defined $here && is_callsign($call);
				next if $call eq $main::mycall;

				eph_del_regex("^PC17\\^$call\\^$ncall");
				
				$conf = $conf eq '*';

				# reject this if we think it is a node already
				my $r = Route::Node::get($call);
				my $u = DXUser->get_current($call) unless $r;
				if ($r || ($u && $u->is_node)) {
					dbg("PCPROT: $call is a node") if isdbg('chanerr');
					next;
				}
				
				$r = Route::User::get($call);
				my $flags = Route::here($here)|Route::conf($conf);
				
				if ($r) {
					if ($r->flags != $flags) {
						$r->flags($flags);
						push @rout, $r;
					}
					$r->addparent($parent);
				} else {
					push @rout, $parent->add_user($call, $flags);
				}
				
				# add this station to the user database, if required
				$call =~ s/-\d+$//o;        # remove ssid for users
				my $user = DXUser->get_current($call);
				$user = DXUser->new($call) if !$user;
				$user->homenode($parent->call) if !$user->homenode;
				$user->node($parent->call);
				$user->lastin($main::systime) unless DXChannel->get($call);
				$user->put;
			}
			
			# queue up any messages (look for privates only)
			DXMsg::queue_msg(1) if $self->state eq 'normal';     

			$self->route_pc16($parent, @rout) if @rout;
			return;
		}
		
		if ($pcno == 17) {		# remove a user
			my $dxchan;
			my $ncall = $field[2];
			my $ucall = $field[1];

			eph_del_regex("^PC16\\^$ncall.*$ucall");
			
			if ($ncall eq $main::mycall) {
				dbg("PCPROT: trying to alter config on this node from outside!") if isdbg('chanerr');
				return;
			}

			my $uref = Route::User::get($ucall);
			unless ($uref) {
				dbg("PCPROT: Route::User $ucall not in config") if isdbg('chanerr');
				return;
			}
			my $parent = Route::Node::get($ncall);
			unless ($parent) {
				dbg("PCPROT: Route::Node $ncall not in config") if isdbg('chanerr');
				return;
			}			

			$dxchan = $parent->dxchan;
			if ($dxchan && $dxchan ne $self) {
				dbg("PCPROT: PC17 from $self->{call} trying to alter locally connected $ncall, ignored!") if isdbg('chanerr');
				return;
			}

			# input filter if required
			return unless $self->in_filter_route($parent);
			
			$parent->del_user($uref);

			if (eph_dup($line)) {
				dbg("PCPROT: dup PC17 detected") if isdbg('chanerr');
				return;
			}

			$self->route_pc17($parent, $uref);
			return;
		}
		
		if ($pcno == 18) {		# link request
			$self->state('init');	

			# first clear out any nodes on this dxchannel
			my $parent = Route::Node::get($self->{call});
			my @rout = $parent->del_nodes;
			$self->route_pc21(@rout, $parent) if @rout;
			$self->send_local_config();
			$self->send(pc20());
			return;             # we don't pass these on
		}
		
		if ($pcno == 19) {		# incoming cluster list
			my $i;
			my $newline = "PC19^";

			if (eph_dup($line)) {
				dbg("PCPROT: dup PC19 detected") if isdbg('chanerr');
				return;
			}

			# new routing list
			my @rout;
			my $parent = Route::Node::get($self->{call});
			unless ($parent) {
				dbg("DXPROT: my parent $self->{call} has disappeared");
				$self->disconnect;
				return;
			}

			# parse the PC19
			for ($i = 1; $i < $#field-1; $i += 4) {
				my $here = $field[$i];
				my $call = uc $field[$i+1];
				my $conf = $field[$i+2];
				my $ver = $field[$i+3];
				next unless defined $here && defined $conf && is_callsign($call);

				eph_del_regex("^PC(?:21\\^$call|17\\^[^\\^]+\\^$call)");
				
				# check for sane parameters
#				$ver = 5000 if $ver eq '0000';
				next if $ver < 5000; # only works with version 5 software
				next if length $call < 3; # min 3 letter callsigns
				next if $call eq $main::mycall;

				# check that this PC19 isn't trying to alter the wrong dxchan
				my $dxchan = DXChannel->get($call);
				if ($dxchan && $dxchan != $self) {
					dbg("PCPROT: PC19 from $self->{call} trying to alter wrong locally connected $call, ignored!") if isdbg('chanerr');
					next;
				}

				# update it if required
				my $r = Route::Node::get($call);
				my $flags = Route::here($here)|Route::conf($conf);
				if ($r) {
					my $ar;
					if ($call ne $parent->call) {
						if ($self->in_filter_route($r)) {
							$ar = $parent->add($call, $ver, $flags);
							push @rout, $ar if $ar;
						} else {
							next;
						}
					}
					if ($r->version ne $ver || $r->flags != $flags) {
						$r->version($ver);
						$r->flags($flags);
						push @rout, $r unless $ar;
					}
				} else {
					if ($call eq $self->{call}) {
						dbg("DXPROT: my channel route for $call has disappeared");
						next;
					};
					
					my $new = Route->new($call);          # throw away
				    if ($self->in_filter_route($new)) {
						my $r = $parent->add($call, $ver, $flags);
						push @rout, $r;
					} else {
						next;
					}
				}

				# unbusy and stop and outgoing mail (ie if somehow we receive another PC19 without a disconnect)
				my $mref = DXMsg::get_busy($call);
				$mref->stop_msg($call) if $mref;
				
				# add this station to the user database, if required (don't remove SSID from nodes)
				my $user = DXUser->get_current($call);
				if (!$user) {
					$user = DXUser->new($call);
					$user->sort('A');
					$user->priv(1);                   # I have relented and defaulted nodes
					$user->lockout(1);
					$user->homenode($call);
					$user->node($call);
				}
				$user->lastin($main::systime) unless DXChannel->get($call);
				$user->put;
			}


			$self->route_pc19(@rout) if @rout;
			return;
		}
		
		if ($pcno == 20) {		# send local configuration
			$self->send_local_config();
			$self->send(pc22());
			$self->state('normal');
			$self->{lastping} = 0;
			return;
		}
		
		if ($pcno == 21) {		# delete a cluster from the list
			my $call = uc $field[1];

			eph_del_regex("^PC1[79].*$call");
			
			# if I get a PC21 from the same callsign as self then treat it
			# as a PC39: I have gone away
			if ($call eq $self->call) {
				$self->disconnect(1);
				return;
			}

			my @rout;
			my $parent = Route::Node::get($self->{call});
			unless ($parent) {
				dbg("DXPROT: my parent $self->{call} has disappeared");
				$self->disconnect;
				return;
			}
			if ($call ne $main::mycall) { # don't allow malicious buggers to disconnect me!
				my $node = Route::Node::get($call);
				if ($node) {

					my $dxchan = DXChannel->get($call);
					if ($dxchan && $dxchan != $self) {
						dbg("PCPROT: PC21 from $self->{call} trying to alter locally connected $call, ignored!") if isdbg('chanerr');
						return;
					}

					# input filter it
					return unless $self->in_filter_route($node);

					# routing objects
					push @rout, $node->del($parent);
				}
			} else {
				dbg("PCPROT: I WILL _NOT_ be disconnected!") if isdbg('chanerr');
				return;
			}

#			if (eph_dup($line)) {
#				dbg("PCPROT: dup PC21 detected") if isdbg('chanerr');
#				return;
#			}

			$self->route_pc21(@rout) if @rout;
			return;
		}
		
		if ($pcno == 22) {
			$self->state('normal');
			$self->{lastping} = 0;
			return;
		}
				
		if ($pcno == 23 || $pcno == 27) { # WWV info
			
			# route 'foreign' pc27s 
			if ($pcno == 27) {
				if ($field[8] ne $main::mycall) {
					$self->route($field[8], $line);
					return;
				}
			}

			return if $rspfcheck and !$self->rspfcheck(1, $field[8], $field[7]);

			# do some de-duping
			my $d = cltounix($field[1], sprintf("%02d18Z", $field[2]));
			my $sfi = unpad($field[3]);
			my $k = unpad($field[4]);
			my $i = unpad($field[5]);
			my ($r) = $field[6] =~ /R=(\d+)/;
			$r = 0 unless $r;
			if (($pcno == 23 && $d < $main::systime - $pc23_max_age) || $d > $main::systime + 1500 || $field[2] < 0 || $field[2] > 23) {
				dbg("PCPROT: WWV Date ($field[1] $field[2]) out of range") if isdbg('chanerr');
				return;
			}
			if (Geomag::dup($d,$sfi,$k,$i,$field[6])) {
				dbg("PCPROT: Dup WWV Spot ignored\n") if isdbg('chanerr');
				return;
			}
			$field[7] =~ s/-\d+$//o;            # remove spotter's ssid
		
			my $wwv = Geomag::update($d, $field[2], $sfi, $k, $i, @field[6..8], $r);

			my $rep;
			eval {
				$rep = Local::wwv($self, $field[1], $field[2], $sfi, $k, $i, @field[6..8], $r);
			};
#			dbg("Local::wwv2 error $@") if isdbg('local') if $@;
			return if $rep;

			# DON'T be silly and send on PC27s!
			return if $pcno == 27;

			# broadcast to the eager world
			send_wwv_spot($self, $line, $d, $field[2], $sfi, $k, $i, @field[6..8]);
			return;
		}
		
		if ($pcno == 24) {		# set here status
			my $call = uc $field[1];
			my ($nref, $uref);
			$nref = Route::Node::get($call);
			$uref = Route::User::get($call);
			return unless $nref || $uref;	# if we don't know where they are, it's pointless sending it on
			
			unless (eph_dup($line)) {
				$nref->here($field[2]) if $nref;
				$uref->here($field[2]) if $uref;
				my $ref = $nref || $uref;
				return unless $self->in_filter_route($ref);
				$self->route_pc24($ref, $field[3]);
			}
			return;
		}
		
		if ($pcno == 25) {      # merge request
			if ($field[1] ne $main::mycall) {
				$self->route($field[1], $line);
				return;
			}
			if ($field[2] eq $main::mycall) {
				dbg("PCPROT: Trying to merge to myself, ignored") if isdbg('chanerr');
				return;
			}

			Log('DXProt', "Merge request for $field[3] spots and $field[4] WWV from $field[2]");
			
			# spots
			if ($field[3] > 0) {
				my @in = reverse Spot::search(1, undef, undef, 0, $field[3]);
				my $in;
				foreach $in (@in) {
					$self->send(pc26(@{$in}[0..4], $field[2]));
				}
			}

			# wwv
			if ($field[4] > 0) {
				my @in = reverse Geomag::search(0, $field[4], time, 1);
				my $in;
				foreach $in (@in) {
					$self->send(pc27(@{$in}[0..5], $field[2]));
				}
			}
			return;
		}

		if (($pcno >= 28 && $pcno <= 33) || $pcno == 40 || $pcno == 42 || $pcno == 49) { # mail/file handling
			return if $pcno == 49 && eph_dup($line);
			if ($pcno == 49 || $field[1] eq $main::mycall) {
				DXMsg::process($self, $line);
			} else {
				$self->route($field[1], $line) unless $self->is_clx;
			}
			return;
		}
		
		if ($pcno == 34 || $pcno == 36) { # remote commands (incoming)
			if (eph_dup($line, $eph_pc34_restime)) {
				dbg("PCPROT: dupe") if isdbg('chanerr');
			} else {
				$self->process_rcmd($field[1], $field[2], $field[2], $field[3]);
			}
			return;
		}
		
		if ($pcno == 35) {		# remote command replies
			eph_del_regex("^PC35\\^$field[2]\\^$field[1]\\^");
			$self->process_rcmd_reply($field[1], $field[2], $field[1], $field[3]);
			return;
		}
		
		# for pc 37 see 44 onwards

		if ($pcno == 38) {		# node connected list from neighbour
			return;
		}
		
		if ($pcno == 39) {		# incoming disconnect
			if ($field[1] eq $self->{call}) {
				$self->disconnect(1);
			} else {
				dbg("PCPROT: came in on wrong channel") if isdbg('chanerr');
			}
			return;
		}
		
		if ($pcno == 41) {		# user info
			my $call = $field[1];

			if (eph_dup($line, $eph_info_restime)) {
				dbg("PCPROT: dupe") if isdbg('chanerr');
				return;
			}
			
			# input filter if required
#			my $ref = Route::get($call) || Route->new($call);
#			return unless $self->in_filter_route($ref);

			if ($field[3] eq $field[2] || $field[3] =~ /^\s*$/) {
				dbg('PCPROT: invalid value') if isdbg('chanerr');
				return;
			}

			# add this station to the user database, if required
			my $user = DXUser->get_current($call);
			$user = DXUser->new($call) if !$user;
			
			if ($field[2] == 1) {
				$user->name($field[3]);
			} elsif ($field[2] == 2) {
				$user->qth($field[3]);
			} elsif ($field[2] == 3) {
				if (is_latlong($field[3])) {
					my ($lat, $long) = DXBearing::stoll($field[3]);
					$user->lat($lat);
					$user->long($long);
					$user->qra(DXBearing::lltoqra($lat, $long));
				} else {
					dbg('PCPROT: not a valid lat/long') if isdbg('chanerr');
					return;
				}
			} elsif ($field[2] == 4) {
				$user->homenode($field[3]);
			} elsif ($field[2] == 5) {
				if (is_qra(uc $field[3])) {
					my ($lat, $long) = DXBearing::qratoll(uc $field[3]);
					$user->lat($lat);
					$user->long($long);
					$user->qra(uc $field[3]);
				} else {
					dbg('PCPROT: not a valid QRA locator') if isdbg('chanerr');
					return;
				}
			}
			$user->lastoper($main::systime);   # to cut down on excessive for/opers being generated
			$user->put;

			unless ($self->{isolate}) {
				DXChannel::broadcast_nodes($line, $self); # send it to everyone but me
			}

#  perhaps this IS what we want after all
#			$self->route_pc41($ref, $call, $field[2], $field[3], $field[4]);
			return;
		}

		if ($pcno == 43) {
			last SWITCH;
		}

		if ($pcno == 37 || $pcno == 44 || $pcno == 45 || $pcno == 46 || $pcno == 47 || $pcno == 48) {
			DXDb::process($self, $line);
			return;
		}
		
		if ($pcno == 50) {		# keep alive/user list
			my $call = $field[1];
			my $node = Route::Node::get($call);
			if ($node) {
				return unless $node->call eq $self->{call};
				$node->usercount($field[2]);

				# input filter if required
				return unless $self->in_filter_route($node);

				$self->route_pc50($node, $field[2], $field[3]) unless eph_dup($line);
			}
			return;
		}
		
		if ($pcno == 51) {		# incoming ping requests/answers
			my $to = $field[1];
			my $from = $field[2];
			my $flag = $field[3];

			
			# is it for us?
			if ($to eq $main::mycall) {
				if ($flag == 1) {
					$self->send(pc51($from, $to, '0'));
				} else {
					# it's a reply, look in the ping list for this one
					my $ref = $pings{$from};
					if ($ref) {
						my $tochan =  DXChannel->get($from);
						while (@$ref) {
							my $r = shift @$ref;
							my $dxchan = DXChannel->get($r->{call});
							next unless $dxchan;
							my $t = tv_interval($r->{t}, [ gettimeofday ]);
							if ($dxchan->is_user) {
								my $s = sprintf "%.2f", $t; 
								my $ave = sprintf "%.2f", $tochan ? ($tochan->{pingave} || $t) : $t;
								$dxchan->send($dxchan->msg('pingi', $from, $s, $ave))
							} elsif ($dxchan->is_node) {
								if ($tochan) {
									my $nopings = $tochan->user->nopings || 2;
									push @{$tochan->{pingtime}}, $t;
									shift @{$tochan->{pingtime}} if @{$tochan->{pingtime}} > 6;

									# cope with a missed ping, this means you must set the pingint large enough
									if ($t > $tochan->{pingint}  && $t < 2 * $tochan->{pingint} ) {
										$t -= $tochan->{pingint};
									}

									# calc smoothed RTT a la TCP
									if (@{$tochan->{pingtime}} == 1) {
										$tochan->{pingave} = $t;
									} else {
										$tochan->{pingave} = $tochan->{pingave} + (($t - $tochan->{pingave}) / 6);
									}
#									my $st;
#									for (@{$tochan->{pingtime}}) {
#										$st += $_;
#									}
#									$tochan->{pingave} = $st / @{$tochan->{pingtime}};
									$tochan->{nopings} = $nopings; # pump up the timer
								}
							} 
						}
					}
				}
			} else {
				if (eph_dup($line)) {
					dbg("PCPROT: dup PC51 detected") if isdbg('chanerr');
					return;
				}
				# route down an appropriate thingy
				$self->route($to, $line);
			}
			return;
		}

		if ($pcno == 75) {		# dunno but route it
			my $call = $field[1];
			if ($call ne $main::mycall) {
				$self->route($call, $line);
			}
			return;
		}

		if ($pcno == 73) {  # WCY broadcasts
			my $call = $field[1];
			
			# do some de-duping
			my $d = cltounix($call, sprintf("%02d18Z", $field[2]));
			if (($pcno == 23 && $d < $main::systime - $pc23_max_age) || $d > $main::systime + 1500 || $field[2] < 0 || $field[2] > 23) {
				dbg("PCPROT: WCY Date ($call $field[2]) out of range") if isdbg('chanerr');
				return;
			}
			@field = map { unpad($_) } @field;
			if (WCY::dup($d)) {
				dbg("PCPROT: Dup WCY Spot ignored\n") if isdbg('chanerr');
				return;
			}
		
			my $wcy = WCY::update($d, @field[2..12]);

			my $rep;
			eval {
				$rep = Local::wcy($self, @field[1..12]);
			};
			# dbg("Local::wcy error $@") if isdbg('local') if $@;
			return if $rep;

			# broadcast to the eager world
			send_wcy_spot($self, $line, $d, @field[2..12]);
			return;
		}

		if ($pcno == 84) { # remote commands (incoming)
			$self->process_rcmd($field[1], $field[2], $field[3], $field[4]);
			return;
		}

		if ($pcno == 85) {		# remote command replies
			$self->process_rcmd_reply($field[1], $field[2], $field[3], $field[4]);
			
			return;
		}
	}
	 
	# if get here then rebroadcast the thing with its Hop count decremented (if
	# there is one). If it has a hop count and it decrements to zero then don't
	# rebroadcast it.
	#
	# NOTE - don't arrive here UNLESS YOU WANT this lump of protocol to be
	#        REBROADCAST!!!!
	#

	if (eph_dup($line)) {
		dbg("PCPROT: Ephemeral dup, dropped") if isdbg('chanerr');
	} else {
		unless ($self->{isolate}) {
			DXChannel::broadcast_nodes($line, $self); # send it to everyone but me
		}
	}
}

#
# This is called from inside the main cluster processing loop and is used
# for despatching commands that are doing some long processing job
#
sub process
{
	my $t = time;
	my @dxchan = DXChannel->get_all();
	my $dxchan;
	my $pc50s;
	
	# send out a pc50 on EVERY channel all at once
	if ($t >= $last_pc50 + $DXProt::pc50_interval) {
		$pc50s = pc50($main::me, scalar DXChannel::get_all_users);
		eph_dup($pc50s);
		$last_pc50 = $t;
	}

	foreach $dxchan (@dxchan) {
		next unless $dxchan->is_node();
		next if $dxchan == $main::me;

		# send the pc50
		$dxchan->send($pc50s) if $pc50s;
		
		# send a ping out on this channel
		if ($dxchan->{pingint} && $t >= $dxchan->{pingint} + $dxchan->{lastping}) {
			if ($dxchan->{nopings} <= 0) {
				$dxchan->disconnect;
			} else {
				addping($main::mycall, $dxchan->call);
				$dxchan->{nopings} -= 1;
				$dxchan->{lastping} = $t;
			}
		}
	}

	# every ten seconds
	if ($t - $last10 >= 10) {	
		# clean out ephemera 

		eph_clean();

		$last10 = $t;
	}
	
	if ($main::systime - 3600 > $last_hour) {
		$last_hour = $main::systime;
	}
}

#
# finish up a pc context
#

#
# some active measures
#

sub send_dx_spot
{
	my $self = shift;
	my $line = shift;
	my @dxchan = DXChannel->get_all();
	my $dxchan;
	
	# send it if it isn't the except list and isn't isolated and still has a hop count
	# taking into account filtering and so on
	foreach $dxchan (@dxchan) {
		next if $dxchan == $main::me;
		next if $dxchan == $self && $self->is_node;
		$dxchan->dx_spot($line, $self->{isolate}, @_, $self->{call});
	}
}

sub dx_spot
{
	my $self = shift;
	my $line = shift;
	my $isolate = shift;
	my ($filter, $hops);

	if ($self->{spotsfilter}) {
		($filter, $hops) = $self->{spotsfilter}->it(@_);
		return unless $filter;
	}
	send_prot_line($self, $filter, $hops, $isolate, $line);
}

sub send_prot_line
{
	my ($self, $filter, $hops, $isolate, $line) = @_;
	my $routeit;
	
	if ($hops) {
		$routeit = $line;
		$routeit =~ s/\^H\d+\^\~$/\^H$hops\^\~/;
	} else {
		$routeit = adjust_hops($self, $line);  # adjust its hop count by node name
		return unless $routeit;
	}
	if ($filter) {
		$self->send($routeit);
	} else {
		$self->send($routeit) unless $self->{isolate} || $isolate;
	}
}


sub send_wwv_spot
{
	my $self = shift;
	my $line = shift;
	my @dxchan = DXChannel->get_all();
	my $dxchan;
	my ($wwv_dxcc, $wwv_itu, $wwv_cq, $org_dxcc, $org_itu, $org_cq) = (0..0);
	my @dxcc = Prefix::extract($_[6]);
	if (@dxcc > 0) {
		$wwv_dxcc = $dxcc[1]->dxcc;
		$wwv_itu = $dxcc[1]->itu;
		$wwv_cq = $dxcc[1]->cq;						
	}
	@dxcc = Prefix::extract($_[7]);
	if (@dxcc > 0) {
		$org_dxcc = $dxcc[1]->dxcc;
		$org_itu = $dxcc[1]->itu;
		$org_cq = $dxcc[1]->cq;						
	}
	
	# send it if it isn't the except list and isn't isolated and still has a hop count
	# taking into account filtering and so on
	foreach $dxchan (@dxchan) {
		next if $dxchan == $main::me;
		next if $dxchan == $self && $self->is_node;
		my $routeit;
		my ($filter, $hops);

		$dxchan->wwv($line, $self->{isolate}, @_, $self->{call}, $wwv_dxcc, $wwv_itu, $wwv_cq, $org_dxcc, $org_itu, $org_cq);
	}
	
}

sub wwv
{
	my $self = shift;
	my $line = shift;
	my $isolate = shift;
	my ($filter, $hops);
	
	if ($self->{wwvfilter}) {
		($filter, $hops) = $self->{wwvfilter}->it(@_);
		return unless $filter;
	}
	send_prot_line($self, $filter, $hops, $isolate, $line)
}

sub send_wcy_spot
{
	my $self = shift;
	my $line = shift;
	my @dxchan = DXChannel->get_all();
	my $dxchan;
	my ($wcy_dxcc, $wcy_itu, $wcy_cq, $org_dxcc, $org_itu, $org_cq) = (0..0);
	my @dxcc = Prefix::extract($_[10]);
	if (@dxcc > 0) {
		$wcy_dxcc = $dxcc[1]->dxcc;
		$wcy_itu = $dxcc[1]->itu;
		$wcy_cq = $dxcc[1]->cq;						
	}
	@dxcc = Prefix::extract($_[11]);
	if (@dxcc > 0) {
		$org_dxcc = $dxcc[1]->dxcc;
		$org_itu = $dxcc[1]->itu;
		$org_cq = $dxcc[1]->cq;						
	}
	
	# send it if it isn't the except list and isn't isolated and still has a hop count
	# taking into account filtering and so on
	foreach $dxchan (@dxchan) {
		next if $dxchan == $main::me;
		next if $dxchan == $self;

		$dxchan->wcy($line, $self->{isolate}, @_, $self->{call}, $wcy_dxcc, $wcy_itu, $wcy_cq, $org_dxcc, $org_itu, $org_cq);
	}
}

sub wcy
{
	my $self = shift;
	my $line = shift;
	my $isolate = shift;
	my ($filter, $hops);

	if ($self->{wcyfilter}) {
		($filter, $hops) = $self->{wcyfilter}->it(@_);
		return unless $filter;
	}
	send_prot_line($self, $filter, $hops, $isolate, $line) if $self->is_clx || $self->is_spider || $self->is_dxnet;
}

# send an announce
sub send_announce
{
	my $self = shift;
	my $line = shift;
	my @dxchan = DXChannel->get_all();
	my $dxchan;
	my $target;
	my $to = 'To ';
	my $text = unpad($_[2]);
				
	if ($_[3] eq '*') {	# sysops
		$target = "SYSOP";
	} elsif ($_[3] gt ' ') { # speciality list handling
		my ($name) = split /\./, $_[3]; 
		$target = "$name"; # put the rest in later (if bothered) 
	} 
	
	if ($_[5] eq '1') {
		$target = "WX"; 
		$to = '';
	}
	$target = "ALL" if !$target;


	# obtain country codes etc 
	my ($ann_dxcc, $ann_itu, $ann_cq, $org_dxcc, $org_itu, $org_cq) = (0..0);
	my @dxcc = Prefix::extract($_[0]);
	if (@dxcc > 0) {
		$ann_dxcc = $dxcc[1]->dxcc;
		$ann_itu = $dxcc[1]->itu;
		$ann_cq = $dxcc[1]->cq;						
	}
	@dxcc = Prefix::extract($_[4]);
	if (@dxcc > 0) {
		$org_dxcc = $dxcc[1]->dxcc;
		$org_itu = $dxcc[1]->itu;
		$org_cq = $dxcc[1]->cq;						
	}

	if ($self->{inannfilter}) {
		my ($filter, $hops) = 
			$self->{inannfilter}->it(@_, $self->{call}, 
									 $ann_dxcc, $ann_itu, $ann_cq,
									 $org_dxcc, $org_itu, $org_cq);
		unless ($filter) {
			dbg("PCPROT: Rejected by input announce filter") if isdbg('chanerr');
			return;
		}
	}

	if (AnnTalk::dup($_[0], $_[1], $_[2])) {
		dbg("PCPROT: Duplicate Announce ignored") if isdbg('chanerr');
		return;
	}

	Log('ann', $target, $_[0], $text);

	# send it if it isn't the except list and isn't isolated and still has a hop count
	# taking into account filtering and so on
	foreach $dxchan (@dxchan) {
		next if $dxchan == $main::me;
		next if $dxchan == $self && $self->is_node;
		$dxchan->announce($line, $self->{isolate}, $to, $target, $text, @_, $self->{call}, $ann_dxcc, $ann_itu, $ann_cq, $org_dxcc, $org_itu, $org_cq);
	}
}

sub announce
{
	my $self = shift;
	my $line = shift;
	my $isolate = shift;
	my $to = shift;
	my $target = shift;
	my $text = shift;
	my ($filter, $hops);

	if ($self->{annfilter}) {
		($filter, $hops) = $self->{annfilter}->it(@_);
		return unless $filter;
	}
	send_prot_line($self, $filter, $hops, $isolate, $line) unless $_[1] eq $main::mycall;
}


sub send_local_config
{
	my $self = shift;
	my $n;
	my @nodes;
	my @localnodes;
	my @remotenodes;

	dbg('DXProt::send_local_config') if isdbg('trace');
	
	# send our nodes
	if ($self->{isolate}) {
		@localnodes = ( $main::routeroot );
	} else {
		# create a list of all the nodes that are not connected to this connection
		# and are not themselves isolated, this to make sure that isolated nodes
        # don't appear outside of this node
		my @dxchan = grep { $_->call ne $main::mycall && $_ != $self && !$_->{isolate} } DXChannel::get_all_nodes();
		@localnodes = map { my $r = Route::Node::get($_->{call}); $r ? $r : () } @dxchan if @dxchan;
		my @intcalls = map { $_->nodes } @localnodes if @localnodes;
		my $ref = Route::Node::get($self->{call});
		my @rnodes = $ref->nodes;
		for my $n (@intcalls) {
			push @remotenodes, Route::Node::get($n) unless grep $n eq $_, @rnodes;
		}
		unshift @localnodes, $main::routeroot;
	}
	
	send_route($self, \&pc19, scalar(@localnodes)+scalar(@remotenodes), @localnodes, @remotenodes);
	
	# get all the users connected on the above nodes and send them out
	foreach $n (@localnodes, @remotenodes) {
		if ($n) {
			send_route($self, \&pc16, 1, $n, map {my $r = Route::User::get($_); $r ? ($r) : ()} $n->users);
		} else {
			dbg("sent a null value") if isdbg('chanerr');
		}
	}
}

#
# route a message down an appropriate interface for a callsign
#
# is called route(to, pcline);
#
sub route
{
	my ($self, $call, $line) = @_;

	if (ref $self && $call eq $self->{call}) {
		dbg("PCPROT: Trying to route back to source, dropped") if isdbg('chanerr');
		return;
	}

	# always send it down the local interface if available
	my $dxchan = DXChannel->get($call);
	unless ($dxchan) {
		my $cl = Route::get($call);
		$dxchan = $cl->dxchan if $cl;
		if (ref $dxchan) {
			if (ref $self && $dxchan eq $self) {
				dbg("PCPROT: Trying to route back to source, dropped") if isdbg('chanerr');
				return;
			}
		}
	}
	if ($dxchan) {
		my $routeit = adjust_hops($dxchan, $line);   # adjust its hop count by node name
		if ($routeit) {
			$dxchan->send($routeit) unless $dxchan == $main::me;
		}
	} else {
		dbg("PCPROT: No route available, dropped") if isdbg('chanerr');
	}
}

#
# obtain the hops from the list for this callsign and pc no 
#

sub get_hops
{
	my $pcno = shift;
	my $hops = $DXProt::hopcount{$pcno};
	$hops = $DXProt::def_hopcount if !$hops;
	return "H$hops";       
}

# 
# adjust the hop count on a per node basis using the user loadable 
# hop table if available or else decrement an existing one
#

sub adjust_hops
{
	my $self = shift;
	my $s = shift;
	my $call = $self->{call};
	my $hops;
	
	if (($hops) = $s =~ /\^H(\d+)\^~?$/o) {
		my ($pcno) = $s =~ /^PC(\d\d)/o;
		confess "$call called adjust_hops with '$s'" unless $pcno;
		my $ref = $nodehops{$call} if %nodehops;
		if ($ref) {
			my $newhops = $ref->{$pcno};
			return "" if defined $newhops && $newhops == 0;
			$newhops = $ref->{default} unless $newhops;
			return "" if defined $newhops && $newhops == 0;
			$newhops = $hops if !$newhops;
			$s =~ s/\^H(\d+)(\^~?)$/\^H$newhops$2/ if $newhops;
		} else {
			# simply decrement it
			$hops--;
			return "" if !$hops;
			$s =~ s/\^H(\d+)(\^~?)$/\^H$hops$2/ if $hops;
		}
	}
	return $s;
}

# 
# load hop tables
#
sub load_hops
{
	my $self = shift;
	return $self->msg('lh1') unless -e "$main::data/hop_table.pl";
	do "$main::data/hop_table.pl";
	return $@ if $@;
	return 0;
}


# add a ping request to the ping queues
sub addping
{
	my ($from, $to) = @_;
	my $ref = $pings{$to} || [];
	my $r = {};
	$r->{call} = $from;
	$r->{t} = [ gettimeofday ];
	route(undef, $to, pc51($to, $main::mycall, 1));
	push @$ref, $r;
	$pings{$to} = $ref;
}

sub process_rcmd
{
	my ($self, $tonode, $fromnode, $user, $cmd) = @_;
	if ($tonode eq $main::mycall) {
		my $ref = DXUser->get_current($fromnode);
		my $cref = Route::Node::get($fromnode);
		Log('rcmd', 'in', $ref->{priv}, $fromnode, $cmd);
		if ($cmd !~ /^\s*rcmd/i && $cref && $ref && $cref->call eq $ref->homenode) { # not allowed to relay RCMDS!
			if ($ref->{priv}) {		# you have to have SOME privilege, the commands have further filtering
				$self->{remotecmd} = 1; # for the benefit of any command that needs to know
				my $oldpriv = $self->{priv};
				$self->{priv} = $ref->{priv}; # assume the user's privilege level
				my @in = (DXCommandmode::run_cmd($self, $cmd));
				$self->{priv} = $oldpriv;
				$self->send_rcmd_reply($main::mycall, $fromnode, $user, @in);
				delete $self->{remotecmd};
			} else {
				$self->send_rcmd_reply($main::mycall, $fromnode, $user, "sorry...!");
			}
		} else {
			$self->send_rcmd_reply($main::mycall, $fromnode, $user, "your attempt is logged, Tut tut tut...!");
		}
	} else {
		my $ref = DXUser->get_current($tonode);
		if ($ref && $ref->is_clx) {
			$self->route($tonode, pc84($fromnode, $tonode, $user, $cmd));
		} else {
			$self->route($tonode, pc34($fromnode, $tonode, $cmd));
		}
	}
}

sub process_rcmd_reply
{
	my ($self, $tonode, $fromnode, $user, $line) = @_;
	if ($tonode eq $main::mycall) {
		my $s = $rcmds{$fromnode};
		if ($s) {
			my $dxchan = DXChannel->get($s->{call});
			my $ref = $user eq $tonode ? $dxchan : (DXChannel->get($user) || $dxchan);
			$ref->send($line) if $ref;
			delete $rcmds{$fromnode} if !$dxchan;
		} else {
			# send unsolicited ones to the sysop
			my $dxchan = DXChannel->get($main::myalias);
			$dxchan->send($line) if $dxchan;
		}
	} else {
		my $ref = DXUser->get_current($tonode);
		if ($ref && $ref->is_clx) {
			$self->route($tonode, pc85($fromnode, $tonode, $user, $line));
		} else {
			$self->route($tonode, pc35($fromnode, $tonode, $line));
		}
	}
}

sub send_rcmd_reply
{
	my $self = shift;
	my $tonode = shift;
	my $fromnode = shift;
	my $user = shift;
	while (@_) {
		my $line = shift;
		$line =~ s/\s*$//;
		Log('rcmd', 'out', $fromnode, $line);
		if ($self->is_clx) {
			$self->send(pc85($main::mycall, $fromnode, $user, "$main::mycall:$line"));
		} else {
			$self->send(pc35($main::mycall, $fromnode, "$main::mycall:$line"));
		}
	}
}

# add a rcmd request to the rcmd queues
sub addrcmd
{
	my ($self, $to, $cmd) = @_;

	my $r = {};
	$r->{call} = $self->{call};
	$r->{t} = $main::systime;
	$r->{cmd} = $cmd;
	$rcmds{$to} = $r;
	
	my $ref = Route::Node::get($to);
	my $dxchan = $ref->dxchan;
	if ($dxchan && $dxchan->is_clx) {
		route(undef, $to, pc84($main::mycall, $to, $self->{call}, $cmd));
	} else {
		route(undef, $to, pc34($main::mycall, $to, $cmd));
	}
}

sub disconnect
{
	my $self = shift;
	my $pc39flag = shift;
	my $call = $self->call;

	return if $self->{disconnecting}++;
	
	unless ($pc39flag && $pc39flag == 1) {
		$self->send_now("D", DXProt::pc39($main::mycall, $self->msg('disc1', "System Op")));
	}

	# get rid of any PC16 and 19s
	eph_del_regex("^PC16\\^$call");
	eph_del_regex("^PC19\\^.*$call");

	# do routing stuff
	my $node = Route::Node::get($call);
	my @rout;
	if ($node) {
		@rout = $node->del($main::routeroot);
	}
	
	# unbusy and stop and outgoing mail
	my $mref = DXMsg::get_busy($call);
	$mref->stop_msg($call) if $mref;
	
	# broadcast to all other nodes that all the nodes connected to via me are gone
	unless ($pc39flag && $pc39flag == 2) {
		$self->route_pc21(@rout) if @rout;
	}

	# remove outstanding pings
	delete $pings{$call};
	
	# I was the last node visited
    $self->user->node($main::mycall);

	# send info to all logged in thingies
	$self->tell_login('logoutn');

	Log('DXProt', $call . " Disconnected");

	$self->SUPER::disconnect;
}


# 
# send a talk message to this thingy
#
sub talk
{
	my ($self, $from, $to, $via, $line, $origin) = @_;
	
	$line =~ s/\^/\\5E/g;			# remove any ^ characters
	$self->send(DXProt::pc10($from, $to, $via, $line, $origin));
	Log('talk', $to, $from, $via?$via:$self->call, $line) unless $origin && $origin ne $main::mycall;
}

# send it if it isn't the except list and isn't isolated and still has a hop count
# taking into account filtering and so on
sub send_route
{
	my $self = shift;
	my $generate = shift;
	my $no = shift;     # the no of things to filter on 
	my $routeit;
	my ($filter, $hops);
	my @rin;
	
	for (; @_ && $no; $no--) {
		my $r = shift;
		
		if (!$self->{isolate} && $self->{routefilter}) {
			$filter = undef;
			if ($r) {
				($filter, $hops) = $self->{routefilter}->it($self->{call}, $self->{dxcc}, $self->{itu}, $self->{cq}, $r->call, $r->dxcc, $r->itu, $r->cq);
				if ($filter) {
					push @rin, $r;
				} else {
					dbg("DXPROT: $self->{call}/" . $r->call . " rejected by output filter") if isdbg('chanerr');
				}
			} else {
				dbg("was sent a null value") if isdbg('chanerr');
			}
		} else {
			push @rin, $r unless $self->{isolate} && $r->call ne $main::mycall;
		}
	}
	if (@rin) {
		foreach my $line (&$generate(@rin, @_)) {
			if ($hops) {
				$routeit = $line;
				$routeit =~ s/\^H\d+\^\~$/\^H$hops\^\~/;
			} else {
				$routeit = adjust_hops($self, $line);  # adjust its hop count by node name
				next unless $routeit;
			}
			$self->send($routeit);
		}
	}
}

sub broadcast_route
{
	my $self = shift;
	my $generate = shift;
	my @dxchan = DXChannel::get_all_nodes();
	my $dxchan;
	my $line;
	
	unless ($self->{isolate}) {
		foreach $dxchan (@dxchan) {
			next if $dxchan == $self;
			next if $dxchan == $main::me;
			$dxchan->send_route($generate, @_);
		}
	}
}

sub route_pc16
{
	my $self = shift;
	broadcast_route($self, \&pc16, 1, @_);
}

sub route_pc17
{
	my $self = shift;
	broadcast_route($self, \&pc17, 1, @_);
}

sub route_pc19
{
	my $self = shift;
	broadcast_route($self, \&pc19, scalar @_, @_);
}

sub route_pc21
{
	my $self = shift;
	broadcast_route($self, \&pc21, scalar @_, @_);
}

sub route_pc24
{
	my $self = shift;
	broadcast_route($self, \&pc24, 1, @_);
}

sub route_pc41
{
	my $self = shift;
	broadcast_route($self, \&pc41, 1, @_);
}

sub route_pc50
{
	my $self = shift;
	broadcast_route($self, \&pc50, 1, @_);
}

sub in_filter_route
{
	my $self = shift;
	my $r = shift;
	my ($filter, $hops) = (1, 1);
	
	if ($self->{inroutefilter}) {
		($filter, $hops) = $self->{inroutefilter}->it($self->{call}, $self->{dxcc}, $self->{itu}, $self->{cq}, $r->call, $r->dxcc, $r->itu, $r->cq);
		dbg("PCPROT: $self->{call}/" . $r->call . ' rejected by in_filter_route') if !$filter && isdbg('chanerr');
	}
	return $filter;
}

sub eph_dup
{
	my $s = shift;
	my $t = shift || $eph_restime;
	my $r;

	# chop the end off
	$s =~ s/\^H\d\d?\^?\~?$//;
	$r = 1 if exists $eph{$s};    # pump up the dup if it keeps circulating
	$eph{$s} = $main::systime + $t;
	return $r;
}

sub eph_del_regex
{
	my $regex = shift;
	my ($key, $val);
	while (($key, $val) = each %eph) {
		if ($key =~ m{$regex}) {
			delete $eph{$key};
		}
	}
}

sub eph_clean
{
	my ($key, $val);
	
	while (($key, $val) = each %eph) {
		if ($main::systime >= $val) {
			delete $eph{$key};
		}
	}
}

sub eph_list
{
	my ($key, $val);
	my @out;

	while (($key, $val) = each %eph) {
		push @out, $key, $val;
	}
	return @out;
}

sub run_cmd
{
	goto &DXCommandmode::run_cmd;
}
1;
__END__ 
