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

use strict;
use vars qw($me $pc11_max_age $pc23_max_age
			$last_hour %pings %rcmds
			%nodehops $baddx $badspotter $badnode $censorpc
			$allowzero $decode_dk0wcy $send_opernam @checklist);

$me = undef;					# the channel id for this cluster
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
	$me = DXProt->new($main::mycall, 0, $user); 
	$me->{here} = 1;
	$me->{state} = "indifferent";
	do "$main::data/hop_table.pl" if -e "$main::data/hop_table.pl";
	confess $@ if $@;
	$me->{sort} = 'S';    # S for spider
	$me->{priv} = 9;
#	$Route::Node::me->adddxchan($me);
}

#
# obtain a new connection this is derived from dxchannel
#

sub new 
{
	my $self = DXChannel::alloc(@_);
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
	
	# remember type of connection
	$self->{consort} = $line;
	$self->{outbound} = $sort eq 'O';
	$self->{priv} = $user->priv || 1;     # other clusters can always be 'normal' users
	$self->{lang} = $user->lang || 'en';
	$self->{isolate} = $user->{isolate};
	$self->{consort} = $line;	# save the connection type
	$self->{here} = 1;

	# get the output filters
	$self->{spotsfilter} = Filter::read_in('spots', $call, 0) || Filter::read_in('spots', 'node_default', 0);
	$self->{wwvfilter} = Filter::read_in('wwv', $call, 0) || Filter::read_in('wwv', 'node_default', 0);
	$self->{wcyfilter} = Filter::read_in('wcy', $call, 0) || Filter::read_in('wcy', 'node_default', 0);
	$self->{annfilter} = Filter::read_in('ann', $call, 0) || Filter::read_in('ann', 'node_default', 0) ;
	$self->{routefilter} = Filter::read_in('route', $call, 0) || Filter::read_in('route', 'node_default', 0) ;


	# get the INPUT filters (these only pertain to Clusters)
	$self->{inspotsfilter} = Filter::read_in('spots', $call, 1) || Filter::read_in('spots', 'node_default', 1);
	$self->{inwwvfilter} = Filter::read_in('wwv', $call, 1) || Filter::read_in('wwv', 'node_default', 1);
	$self->{inwcyfilter} = Filter::read_in('wcy', $call, 1) || Filter::read_in('wcy', 'node_default', 1);
	$self->{inannfilter} = Filter::read_in('ann', $call, 1) || Filter::read_in('ann', 'node_default', 1);
	$self->{inroutefilter} = Filter::read_in('route', $call, 1) || Filter::read_in('route', 'node_default', 1);
	
	# set unbuffered and no echo
	$self->send_now('B',"0");
	$self->send_now('E',"0");
	
	# ping neighbour node stuff
	my $ping = $user->pingint;
	$ping = 5*60 unless defined $ping;
	$self->{pingint} = $ping;
	$self->{nopings} = $user->nopings || 2;
	$self->{pingtime} = [ ];
	$self->{pingave} = 0;

	# send initialisation string
	unless ($self->{outbound}) {
		$self->send(pc18());
		$self->{lastping} = $main::systime;
	} else {
		$self->{lastping} = $main::systime + ($self->pingint / 2);
	}
	$self->state('init');
	$self->{pc50_t} = $main::systime;

	# send info to all logged in thingies
	$self->tell_login('loginn');

	# add this node to the table, the values get filled in later
	$main::routeroot->add($call);

	Log('DXProt', "$call connected");
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
						
	# ignore any lines that don't start with PC
	return if !$field[0] =~ /^PC/;
	
	# process PC frames
	my ($pcno) = $field[0] =~ /^PC(\d\d)/; # just get the number
	return unless $pcno;
	return if $pcno < 10 || $pcno > 99;

	# check for and dump bad protocol messages
	my $n = check($pcno, @field);
	if ($n) {
		dbg('chan', "PCPROT: bad field $n, dumped (" . parray($checklist[$pcno-10]) . ")");
		return;
	}

	# local processing 1
	my $pcr;
	eval {
		$pcr = Local::pcprot($self, $pcno, @field);
	};
#	dbg('local', "Local::pcprot error $@") if $@;
	return if $pcr;
	
 SWITCH: {
		if ($pcno == 10) {		# incoming talk

			# will we allow it at all?
			if ($censorpc) {
				my @bad;
				if (@bad = BadWords::check($field[3])) {
					dbg('chan', "PCPROT: Bad words: @bad, dropped" );
					return;
				}
			}

			# is it for me or one of mine?
			my ($to, $via, $call, $dxchan);
			if ($field[5] gt ' ') {
				$call = $via = $field[2];
				$to = $field[5];
			} else {
				$call = $to = $field[2];
			}
			$dxchan = DXChannel->get($call);
			if ($dxchan && $dxchan->is_user) {
				$field[3] =~ s/\%5E/^/g;
				$dxchan->talk($field[1], $to, $via, $field[3]);
			} else {
				$self->route($field[2], $line); # relay it on its way
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
			
			# if this is a 'nodx' node then ignore it
			if ($badnode->in($field[7])) {
				dbg('chan', "PCPROT: Bad Node, dropped");
				return;
			}
			
			# if this is a 'bad spotter' user then ignore it
			if ($badspotter->in($field[6])) {
				dbg('chan', "PCPROT: Bad Spotter, dropped");
				return;
			}
			
			# convert the date to a unix date
			my $d = cltounix($field[3], $field[4]);
			# bang out (and don't pass on) if date is invalid or the spot is too old (or too young)
			if (!$d || ($pcno == 11 && ($d < $main::systime - $pc11_max_age || $d > $main::systime + 900))) {
				dbg('chan', "PCPROT: Spot ignored, invalid date or out of range ($field[3] $field[4])\n");
				return;
			}

			# is it 'baddx'
			if ($baddx->in($field[2])) {
				dbg('chan', "PCPROT: Bad DX spot, ignored");
				return;
			}
			
			# do some de-duping
			$field[5] =~ s/^\s+//;      # take any leading blanks off
			$field[2] = unpad($field[2]);	# take off leading and trailing blanks from spotted callsign
			if ($field[2] =~ /BUST\w*$/) {
				dbg('chan', "PCPROT: useless 'BUSTED' spot");
				return;
			}
			if (Spot::dup($field[1], $field[2], $d, $field[5])) {
				dbg('chan', "PCPROT: Duplicate Spot ignored\n");
				return;
			}
			if ($censorpc) {
				my @bad;
				if (@bad = BadWords::check($field[5])) {
					dbg('chan', "PCPROT: Bad words: @bad, dropped" );
					return;
				}
			}

			my @spot = Spot::prepare($field[1], $field[2], $d, $field[5], $field[6], $field[7]);
			# global spot filtering on INPUT
			if ($self->{inspotsfilter}) {
				my ($filter, $hops) = $self->{inspotsfilter}->it(@spot);
				unless ($filter) {
					dbg('chan', "PCPROT: Rejected by filter");
					return;
				}
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
				unless ($qra && DXBearing::is_qra($qra)) {
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
					if ($send_opernam && $main::systime > $last + $DXUser::lastoperinterval && $to && ($node = Route::Node::get($to)) ) {
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
#			dbg('local', "Local::spot1 error $@") if $@;
			return if $r;

			# DON'T be silly and send on PC26s!
			return if $pcno == 26;

			# send out the filtered spots
			send_dx_spot($self, $line, @spot) if @spot;
			return;
		}
		
		if ($pcno == 12) {		# announces
			# announce duplicate checking
			$field[3] =~ s/^\s+//;  # remove leading blanks
			if (AnnTalk::dup($field[1], $field[2], $field[3])) {
				dbg('chan', "PCPROT: Duplicate Announce ignored");
				return;
			}

			if ($censorpc) {
				my @bad;
				if (@bad = BadWords::check($field[3])) {
					dbg('chan', "PCPROT: Bad words: @bad, dropped" );
					return;
				}
			}
			
			if ($field[2] eq '*' || $field[2] eq $main::mycall) {
				
				# global ann filtering on INPUT
				if ($self->{inannfilter}) {
					my ($ann_dxcc, $ann_itu, $ann_cq, $org_dxcc, $org_itu, $org_cq) = (0..0);
					my @dxcc = Prefix::extract($field[1]);
					if (@dxcc > 0) {
						$ann_dxcc = $dxcc[1]->dxcc;
						$ann_itu = $dxcc[1]->itu;
						$ann_cq = $dxcc[1]->cq();						
					}
					@dxcc = Prefix::extract($field[5]);
					if (@dxcc > 0) {
						$org_dxcc = $dxcc[1]->dxcc;
						$org_itu = $dxcc[1]->itu;
						$org_cq = $dxcc[1]->cq();						
					}
					my ($filter, $hops) = $self->{inannfilter}->it(@field[1..6], $self->{call}, 
													$ann_dxcc, $ann_itu, $ann_cq, $org_dxcc, $org_itu, $org_cq);
					unless ($filter) {
						dbg('chan', "PCPROT: Rejected by filter");
						return;
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

			# general checks
			my $dxchan;
			my $newline = "PC16^";
			
			if ($field[1] eq $main::mycall || $field[2] eq $main::mycall) {
				dbg('chan', "PCPROT: trying to alter config on this node from outside!");
				return;
			}
			if ($field[2] eq $main::myalias && DXChannel->get($field[1])) {
				dbg('chan', "PCPROT: trying to connect sysop from outside!");
				return;
			}
			if (($dxchan = DXChannel->get($field[1])) && $dxchan != $self) {
				dbg('chan', "PCPROT: $field[1] connected locally");
				return;
			}

			my $node = Route::Node::get($field[1]); 
			unless ($node) {
				dbg('chan', "PCPROT: Node $field[1] not in config");
				return;
			}
			my $i;
			my @rout;
			for ($i = 2; $i < $#field; $i++) {
				my ($call, $conf, $here) = $field[$i] =~ /^(\S+) (\S) (\d)/o;
				next unless $call && $conf && defined $here && is_callsign($call);
				$conf = $conf eq '*';

				push @rout, $node->add_user($call, Route::here($here)|Route::conf($conf));
				
				# add this station to the user database, if required
				$call =~ s/-\d+$//o;        # remove ssid for users
				my $user = DXUser->get_current($call);
				$user = DXUser->new($call) if !$user;
				$user->homenode($node->call) if !$user->homenode;
				$user->node($node->call);
				$user->lastin($main::systime) unless DXChannel->get($call);
				$user->put;
			}

			
			# queue up any messages (look for privates only)
			DXMsg::queue_msg(1) if $self->state eq 'normal';     

			dbg('route', "B/C PC16 on $field[1] for: " . join(',', map{$_->call} @rout)) if @rout;
			$self->route_pc16($node, @rout) if @rout;
			return;
		}
		
		if ($pcno == 17) {		# remove a user
			my $dxchan;
			if ($field[1] eq $main::mycall || $field[2] eq $main::mycall) {
				dbg('chan', "PCPROT: trying to alter config on this node from outside!");
				return;
			}
			if ($field[1] eq $main::myalias && DXChannel->get($field[1])) {
				dbg('chan', "PCPROT: trying to disconnect sysop from outside!");
				return;
			}
			if ($dxchan = DXChannel->get($field[1])) {
				dbg('chan', "PCPROT: $field[1] connected locally");
				return;
			}

			my $node = Route::Node::get($field[2]);
			unless ($node) {
				dbg('chan', "PCPROT: Route::Node $field[2] not in config");
				return;
			}
			my @rout = $node->del_user($field[1]);
			dbg('route', "B/C PC17 on $field[2] for: $field[1]");
			$self->route_pc17($node, @rout) if @rout;
			return;
		}
		
		if ($pcno == 18) {		# link request
			$self->state('init');	

			# first clear out any nodes on this dxchannel
			my $node = Route::Node::get($self->{call});
			my @rout;
			for ($node->nodes) {
				push @rout, $_->del_node;
			}
			$self->route_pc21(@rout, $node);
			$self->send_local_config();
			$self->send(pc20());
			return;             # we don't pass these on
		}
		
		if ($pcno == 19) {		# incoming cluster list
			my $i;
			my $newline = "PC19^";

			# new routing list
			my @rout;
			my $node = Route::Node::get($self->{call});

			# parse the PC19
			for ($i = 1; $i < $#field-1; $i += 4) {
				my $here = $field[$i];
				my $call = uc $field[$i+1];
				my $conf = $field[$i+2];
				my $ver = $field[$i+3];
				next unless defined $here && defined $conf && is_callsign($call);
				# check for sane parameters
				$ver = 5000 if $ver eq '0000';
				next if $ver < 5000; # only works with version 5 software
				next if length $call < 3; # min 3 letter callsigns

				# update it if required
				if ($node->call eq $call && !$node->version) {
					$node->version($ver);
					$node->flags(Route::here($here)|Route::conf($conf));
					push @rout, $node;
				} elsif ($node->call ne $call) {
					my $r = $node->add($call, $ver, Route::here($here)|Route::conf($conf));
					push @rout, $r if $r;
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
					$self->{priv} = 1;                # to user RCMDs allowed
					$user->homenode($call);
					$user->node($call);
				}
				$user->lastin($main::systime) unless DXChannel->get($call);
				$user->put;
			}

			dbg('route', "B/C PC19 for: " . join(',', map{$_->call} @rout)) if @rout;
			
			$self->route_pc19(@rout) if @rout;
			return;
		}
		
		if ($pcno == 20) {		# send local configuration
			$self->send_local_config();
			$self->send(pc22());
			$self->state('normal');
			return;
		}
		
		if ($pcno == 21) {		# delete a cluster from the list
			my $call = uc $field[1];
			my @rout;
			my $node = Route::Node::get($call);
			
			if ($call ne $main::mycall) { # don't allow malicious buggers to disconnect me!
				if ($call eq $self->{call}) {
					dbg('chan', "PCPROT: Trying to disconnect myself with PC21");
					return;
				}

				# routing objects
				if ($node) {
					push @rout, $node->del_node($call);
				} else {
					dbg('chan', "PCPROT: Route::Node $call not in config");
				}
			} else {
				dbg('chan', "PCPROT: I WILL _NOT_ be disconnected!");
				return;
			}
			dbg('route', "B/C PC21 for: " . join(',', (map{$_->call} @rout))) if @rout;
			
			$self->route_pc21(@rout) if @rout;
			return;
		}
		
		if ($pcno == 22) {
			$self->state('normal');
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

			# do some de-duping
			my $d = cltounix($field[1], sprintf("%02d18Z", $field[2]));
			my $sfi = unpad($field[3]);
			my $k = unpad($field[4]);
			my $i = unpad($field[5]);
			my ($r) = $field[6] =~ /R=(\d+)/;
			$r = 0 unless $r;
			if (($pcno == 23 && $d < $main::systime - $pc23_max_age) || $d > $main::systime + 1500 || $field[2] < 0 || $field[2] > 23) {
				dbg('chan', "PCPROT: WWV Date ($field[1] $field[2]) out of range");
				return;
			}
			if (Geomag::dup($d,$sfi,$k,$i,$field[6])) {
				dbg('chan', "PCPROT: Dup WWV Spot ignored\n");
				return;
			}
			$field[7] =~ s/-\d+$//o;            # remove spotter's ssid
		
			my $wwv = Geomag::update($d, $field[2], $sfi, $k, $i, @field[6..8], $r);

			my $rep;
			eval {
				$rep = Local::wwv($self, $field[1], $field[2], $sfi, $k, $i, @field[6..8], $r);
			};
#			dbg('local', "Local::wwv2 error $@") if $@;
			return if $rep;

			# DON'T be silly and send on PC27s!
			return if $pcno == 27;

			# broadcast to the eager world
			send_wwv_spot($self, $line, $d, $field[2], $sfi, $k, $i, @field[6..8]);
			return;
		}
		
		if ($pcno == 24) {		# set here status
			my $call = uc $field[1];
			my $ref = Route::Node::get($call);
			$ref->here($field[2]) if $ref;
			$ref = Route::User::get($call);
			$ref->here($field[2]) if $ref;
			last SWITCH;
		}
		
		if ($pcno == 25) {      # merge request
			if ($field[1] ne $main::mycall) {
				$self->route($field[1], $line);
				return;
			}
			if ($field[2] eq $main::mycall) {
				dbg('chan', "PCPROT: Trying to merge to myself, ignored");
				return;
			}

			Log('DXProt', "Merge request for $field[3] spots and $field[4] WWV from $field[1]");
			
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
			if ($pcno == 49 || $field[1] eq $main::mycall) {
				DXMsg::process($self, $line);
			} else {
				$self->route($field[1], $line) unless $self->is_clx;
			}
			return;
		}
		
		if ($pcno == 34 || $pcno == 36) { # remote commands (incoming)
			if ($field[1] eq $main::mycall) {
				my $ref = DXUser->get_current($field[2]);
				my $cref = Route::Node::get($field[2]);
				Log('rcmd', 'in', $ref->{priv}, $field[2], $field[3]);
				unless (!$cref || !$ref || $cref->call ne $ref->homenode) {    # not allowed to relay RCMDS!
					if ($ref->{priv}) {	# you have to have SOME privilege, the commands have further filtering
						$self->{remotecmd} = 1; # for the benefit of any command that needs to know
						my $oldpriv = $self->{priv};
						$self->{priv} = $ref->{priv};     # assume the user's privilege level
						my @in = (DXCommandmode::run_cmd($self, $field[3]));
						$self->{priv} = $oldpriv;
						for (@in) {
							s/\s*$//og;
							$self->send(pc35($main::mycall, $field[2], "$main::mycall:$_"));
							Log('rcmd', 'out', $field[2], $_);
						}
						delete $self->{remotecmd};
					} else {
						$self->send(pc35($main::mycall, $field[2], "$main::mycall:sorry...!"));
					}
				} else {
					$self->send(pc35($main::mycall, $field[2], "$main::mycall:your attempt is logged, Tut tut tut...!"));
				}
			} else {
				my $ref = DXUser->get_current($field[1]);
				if ($ref && $ref->is_clx) {
					$self->route($field[1], pc84($field[2], $field[1], $field[2], $field[3]));
				} else {
					$self->route($field[1], $line);
				}
			}
			return;
		}
		
		if ($pcno == 35) {		# remote command replies
			if ($field[1] eq $main::mycall) {
				my $s = $rcmds{$field[2]};
				if ($s) {
					my $dxchan = DXChannel->get($s->{call});
					$dxchan->send($field[3]) if $dxchan;
					delete $rcmds{$field[2]} if !$dxchan;
				} else {
					# send unsolicited ones to the sysop
					my $dxchan = DXChannel->get($main::myalias);
					$dxchan->send($field[3]) if $dxchan;
				}
			} else {
				my $ref = DXUser->get_current($field[1]);
				if ($ref && $ref->is_clx) {
					$self->route($field[1], pc85($field[2], $field[1], $field[2], $field[3]));
				} else {
					$self->route($field[1], $line);
				}
			}
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
				dbg('chan', "PCPROT: came in on wrong channel");
			}
			return;
		}
		
		if ($pcno == 41) {		# user info
			# add this station to the user database, if required
			my $user = DXUser->get_current($field[1]);
			$user = DXUser->new($field[1]) if !$user;
			
			if ($field[2] == 1) {
				$user->name($field[3]);
			} elsif ($field[2] == 2) {
				$user->qth($field[3]);
			} elsif ($field[2] == 3) {
				my ($lat, $long) = DXBearing::stoll($field[3]);
				$user->lat($lat);
				$user->long($long);
				$user->qra(DXBearing::lltoqra($lat, $long)) unless $user->qra && DXBearing::is_qra($user->qra);
			} elsif ($field[2] == 4) {
				$user->homenode($field[3]);
			}
			$user->lastoper($main::systime);   # to cut down on excessive for/opers being generated
			$user->put;
			last SWITCH;
		}
		if ($pcno == 43) {
			last SWITCH;
		}
		if ($pcno == 37 || $pcno == 44 || $pcno == 45 || $pcno == 46 || $pcno == 47 || $pcno == 48) {
			DXDb::process($self, $line);
			return;
		}
		
		if ($pcno == 50) {		# keep alive/user list
			my $node = Route::Node::get($field[1]);
			if ($node) {
				return unless $node->call eq $self->{call};
				$node->usercount($field[2]);
			}
			last SWITCH;
		}
		
		if ($pcno == 51) {		# incoming ping requests/answers
			
			# is it for us?
			if ($field[1] eq $main::mycall) {
				my $flag = $field[3];
				if ($flag == 1) {
					$self->send(pc51($field[2], $field[1], '0'));
				} else {
					# it's a reply, look in the ping list for this one
					my $ref = $pings{$field[2]};
					if ($ref) {
						my $tochan =  DXChannel->get($field[2]);
						while (@$ref) {
							my $r = shift @$ref;
							my $dxchan = DXChannel->get($r->{call});
							next unless $dxchan;
							my $t = tv_interval($r->{t}, [ gettimeofday ]);
							if ($dxchan->is_user) {
								my $s = sprintf "%.2f", $t; 
								my $ave = sprintf "%.2f", $tochan ? ($tochan->{pingave} || $t) : $t;
								$dxchan->send($dxchan->msg('pingi', $field[2], $s, $ave))
							} elsif ($dxchan->is_node) {
								if ($tochan) {
									$tochan->{nopings} = $tochan->user->nopings || 2; # pump up the timer
									push @{$tochan->{pingtime}}, $t;
									shift @{$tochan->{pingtime}} if @{$tochan->{pingtime}} > 6;
									my $st;
									for (@{$tochan->{pingtime}}) {
										$st += $_;
									}
									$tochan->{pingave} = $st / @{$tochan->{pingtime}};
								}
							} 
						}
					}
				}
			} else {
				# route down an appropriate thingy
				$self->route($field[1], $line);
			}
			return;
		}

		if ($pcno == 75) {		# dunno but route it
			if ($field[1] ne $main::mycall) {
				$self->route($field[1], $line);
			}
			return;
		}

		if ($pcno == 73) {  # WCY broadcasts
			
			# do some de-duping
			my $d = cltounix($field[1], sprintf("%02d18Z", $field[2]));
			if (($pcno == 23 && $d < $main::systime - $pc23_max_age) || $d > $main::systime + 1500 || $field[2] < 0 || $field[2] > 23) {
				dbg('chan', "PCPROT: WCY Date ($field[1] $field[2]) out of range");
				return;
			}
			@field = map { unpad($_) } @field;
			if (WCY::dup($d,@field[3..7])) {
				dbg('chan', "PCPROT: Dup WCY Spot ignored\n");
				return;
			}
		
			my $wcy = WCY::update($d, @field[2..12]);

			my $rep;
			eval {
				$rep = Local::wwv($self, @field[1..12]);
			};
			# dbg('local', "Local::wcy error $@") if $@;
			return if $rep;

			# broadcast to the eager world
			send_wcy_spot($self, $line, $d, @field[2..12]);
			return;
		}

		if ($pcno == 84) { # remote commands (incoming)
			if ($field[1] eq $main::mycall) {
				my $ref = DXUser->get_current($field[2]);
				my $cref = Route::Node::get($field[2]);
				Log('rcmd', 'in', $ref->{priv}, $field[2], $field[4]);
				unless ($field[4] =~ /rcmd/i || !$cref || !$ref || $cref->call ne $ref->homenode) {    # not allowed to relay RCMDS!
					if ($ref->{priv}) {	# you have to have SOME privilege, the commands have further filtering
						$self->{remotecmd} = 1; # for the benefit of any command that needs to know
						my $oldpriv = $self->{priv};
						$self->{priv} = $ref->{priv};     # assume the user's privilege level
						my @in = (DXCommandmode::run_cmd($self, $field[4]));
						$self->{priv} = $oldpriv;
						for (@in) {
							s/\s*$//og;
							$self->send(pc85($main::mycall, $field[2], $field[3], "$main::mycall:$_"));
							Log('rcmd', 'out', $field[2], $_);
						}
						delete $self->{remotecmd};
					} else {
						$self->send(pc85($main::mycall, $field[2], $field[3], "$main::mycall:sorry...!"));
					}
				} else {
					$self->send(pc85($main::mycall, $field[2], $field[3],"$main::mycall:your attempt is logged, Tut tut tut...!"));
				}
			} else {
				my $ref = DXUser->get_current($field[1]);
				if ($ref && $ref->is_clx) {
					$self->route($field[1], $line);
				} else {
					$self->route($field[1], pc34($field[2], $field[1], $field[4]));
				}
			}
			return;
		}

		if ($pcno == 85) {		# remote command replies
			if ($field[1] eq $main::mycall) {
				my $dxchan = DXChannel->get($field[3]);
				if ($dxchan) {
					$dxchan->send($field[4]);
				} else {
					my $s = $rcmds{$field[2]};
					if ($s) {
						$dxchan = DXChannel->get($s->{call});
						$dxchan->send($field[4]) if $dxchan;
						delete $rcmds{$field[2]} if !$dxchan;
					} else {
						# send unsolicited ones to the sysop
						my $dxchan = DXChannel->get($main::myalias);
						$dxchan->send($field[4]) if $dxchan;
					}
				}
			} else {
				my $ref = DXUser->get_current($field[1]);
				if ($ref && $ref->is_clx) {
					$self->route($field[1], $line);
				} else {
					$self->route($field[1], pc35($field[2], $field[1], $field[4]));
				}
			}
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
	 
	unless ($self->{isolate}) {
		broadcast_ak1a($line, $self); # send it to everyone but me
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
	
	foreach $dxchan (@dxchan) {
		next unless $dxchan->is_node();
		next if $dxchan == $me;
		
		# send a pc50 out on this channel
		$dxchan->{pc50_t} = $main::systime unless exists $dxchan->{pc50_t};
		if ($t >= $dxchan->{pc50_t} + $DXProt::pc50_interval) {
			$dxchan->send(pc50(scalar DXChannel::get_all_users));
			$dxchan->{pc50_t} = $t;
		} 

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
	
	my $key;
	my $val;
	my $cutoff;
	if ($main::systime - 3600 > $last_hour) {
#		Spot::process;
#		Geomag::process;
#		AnnTalk::process;
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
		next if $dxchan == $me;
		my $routeit;
		my ($filter, $hops);

		if ($dxchan->{spotsfilter}) {
		    ($filter, $hops) = $dxchan->{spotsfilter}->it(@_, $self->{call} );
			next unless $filter;
		}
		
		if ($dxchan->is_node) {
			next if $dxchan == $self;
			if ($hops) {
				$routeit = $line;
				$routeit =~ s/\^H\d+\^\~$/\^H$hops\^\~/;
			} else {
				$routeit = adjust_hops($dxchan, $line);  # adjust its hop count by node name
				next unless $routeit;
			}
			if ($filter) {
				$dxchan->send($routeit) if $routeit;
			} else {
				$dxchan->send($routeit) unless $dxchan->{isolate} || $self->{isolate};
			}
		} elsif ($dxchan->is_user && $dxchan->{dx}) {
			my $buf = Spot::formatb($dxchan->{user}->wantgrid, $_[0], $_[1], $_[2], $_[3], $_[4]);
			$buf .= "\a\a" if $dxchan->{beep};
			$buf =~ s/\%5E/^/g;
			if ($dxchan->{state} eq 'prompt' || $dxchan->{state} eq 'talk') {
				$dxchan->send($buf);
			} else {
				$dxchan->delay($buf);
			}
		}					
	}
}

sub send_wwv_spot
{
	my $self = shift;
	my $line = shift;
	my @dxchan = DXChannel->get_all();
	my $dxchan;
	my ($wwv_dxcc, $wwv_itu, $wwv_cq, $org_dxcc, $org_itu, $org_cq) = (0..0);
	my @dxcc = Prefix::extract($_[7]);
	if (@dxcc > 0) {
		$wwv_dxcc = $dxcc[1]->dxcc;
		$wwv_itu = $dxcc[1]->itu;
		$wwv_cq = $dxcc[1]->cq;						
	}
	@dxcc = Prefix::extract($_[8]);
	if (@dxcc > 0) {
		$org_dxcc = $dxcc[1]->dxcc;
		$org_itu = $dxcc[1]->itu;
		$org_cq = $dxcc[1]->cq;						
	}
	
	# send it if it isn't the except list and isn't isolated and still has a hop count
	# taking into account filtering and so on
	foreach $dxchan (@dxchan) {
		next if $dxchan == $self;
		next if $dxchan == $me;
		my $routeit;
		my ($filter, $hops);

		if ($dxchan->{wwvfilter}) {
			($filter, $hops) = $dxchan->{wwvfilter}->it(@_, $self->{call}, $wwv_dxcc, $wwv_itu, $wwv_cq, $org_dxcc, $org_itu, $org_cq);
			 next unless $filter;
		}
		if ($dxchan->is_node) {
			if ($hops) {
				$routeit = $line;
				$routeit =~ s/\^H\d+\^\~$/\^H$hops\^\~/;
			} else {
				$routeit = adjust_hops($dxchan, $line);  # adjust its hop count by node name
				next unless $routeit;
			}
			if ($filter) {
				$dxchan->send($routeit) if $routeit;
			} else {
				$dxchan->send($routeit) unless $dxchan->{isolate} || $self->{isolate};
				
			}
		} elsif ($dxchan->is_user && $dxchan->{wwv}) {
			my $buf = "WWV de $_[6] <$_[1]>:   SFI=$_[2], A=$_[3], K=$_[4], $_[5]";
			$buf .= "\a\a" if $dxchan->{beep};
			if ($dxchan->{state} eq 'prompt' || $dxchan->{state} eq 'talk') {
				$dxchan->send($buf);
			} else {
				$dxchan->delay($buf);
			}
		}					
	}
}

sub send_wcy_spot
{
	my $self = shift;
	my $line = shift;
	my @dxchan = DXChannel->get_all();
	my $dxchan;
	my ($wcy_dxcc, $wcy_itu, $wcy_cq, $org_dxcc, $org_itu, $org_cq) = (0..0);
	my @dxcc = Prefix::extract($_[11]);
	if (@dxcc > 0) {
		$wcy_dxcc = $dxcc[1]->dxcc;
		$wcy_itu = $dxcc[1]->itu;
		$wcy_cq = $dxcc[1]->cq;						
	}
	@dxcc = Prefix::extract($_[12]);
	if (@dxcc > 0) {
		$org_dxcc = $dxcc[1]->dxcc;
		$org_itu = $dxcc[1]->itu;
		$org_cq = $dxcc[1]->cq;						
	}
	
	# send it if it isn't the except list and isn't isolated and still has a hop count
	# taking into account filtering and so on
	foreach $dxchan (@dxchan) {
		next if $dxchan == $me;
		my $routeit;
		my ($filter, $hops);

		if ($dxchan->{wcyfilter}) {
			($filter, $hops) = $dxchan->{wcyfilter}->it(@_, $self->{call}, $wcy_dxcc, $wcy_itu, $wcy_cq, $org_dxcc, $org_itu, $org_cq);
			 next unless $filter;
		}
		if ($dxchan->is_clx || $dxchan->is_spider || $dxchan->is_dxnet) {
			if ($hops) {
				$routeit = $line;
				$routeit =~ s/\^H\d+\^\~$/\^H$hops\^\~/;
			} else {
				$routeit = adjust_hops($dxchan, $line);  # adjust its hop count by node name
				next unless $routeit;
			}
			if ($filter) {
				$dxchan->send($routeit) if $routeit;
			} else {
				$dxchan->send($routeit) unless $dxchan->{isolate} || $self->{isolate};
			}
		} elsif ($dxchan->is_user && $dxchan->{wcy}) {
			my $buf = "WCY de $_[10] <$_[1]> : K=$_[4] expK=$_[5] A=$_[3] R=$_[6] SFI=$_[2] SA=$_[7] GMF=$_[8] Au=$_[9]";
			$buf .= "\a\a" if $dxchan->{beep};
			if ($dxchan->{state} eq 'prompt' || $dxchan->{state} eq 'talk') {
				$dxchan->send($buf);
			} else {
				$dxchan->delay($buf);
			}
		}					
	}
}

# send an announce
sub send_announce
{
	my $self = shift;
	my $line = shift;
	my @dxchan = DXChannel->get_all();
	my $dxchan;
	my $text = unpad($_[2]);
	my $target;
	my $to = 'To ';
				
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
	
	Log('ann', $target, $_[0], $text);

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

	# send it if it isn't the except list and isn't isolated and still has a hop count
	# taking into account filtering and so on
	foreach $dxchan (@dxchan) {
		next if $dxchan == $self;
		next if $dxchan == $me;
		my $routeit;
		my ($filter, $hops);

		if ($dxchan->{annfilter}) {
			($filter, $hops) = $dxchan->{annfilter}->it(@_, $self->{call}, $ann_dxcc, $ann_itu, $ann_cq, $org_dxcc, $org_itu, $org_cq);
			next unless $filter;
		} 
		if ($dxchan->is_node && $_[1] ne $main::mycall) {  # i.e not specifically routed to me
			if ($hops) {
				$routeit = $line;
				$routeit =~ s/\^H\d+\^\~$/\^H$hops\^\~/;
			} else {
				$routeit = adjust_hops($dxchan, $line);  # adjust its hop count by node name
				next unless $routeit;
			}
			if ($filter) {
				$dxchan->send($routeit) if $routeit;
			} else {
				$dxchan->send($routeit) unless $dxchan->{isolate} || $self->{isolate};
				
			}
		} elsif ($dxchan->is_user) {
			unless ($dxchan->{ann}) {
				next if $_[0] ne $main::myalias && $_[0] ne $main::mycall;
			}
			next if $target eq 'SYSOP' && $dxchan->{priv} < 5;
			my $buf = "$to$target de $_[0]: $text";
			$buf =~ s/\%5E/^/g;
			$buf .= "\a\a" if $dxchan->{beep};
			if ($dxchan->{state} eq 'prompt' || $dxchan->{state} eq 'talk') {
				$dxchan->send($buf);
			} else {
				$dxchan->delay($buf);
			}
		}					
	}
}

sub send_local_config
{
	my $self = shift;
	my $n;
	my @nodes;
	my @localcalls;
	my @remotecalls;
		
	# send our nodes
	if ($self->{isolate}) {
		@localcalls = ( $main::mycall );
	} else {
		# create a list of all the nodes that are not connected to this connection
		# and are not themselves isolated, this to make sure that isolated nodes
        # don't appear outside of this node
		my @dxchan = grep { $_->call ne $main::mycall && $_->call ne $self->{call} && !$_->{isolate} } DXChannel::get_all_nodes();
		@localcalls = map { $_->{call} } @dxchan if @dxchan;
		@remotecalls = map {my $r = Route::Node::get($_); $r ? $r->rnodes(@localcalls, $main::mycall, $self->{call}) : () } @localcalls if @localcalls;
		unshift @localcalls, $main::mycall;
	}
	@nodes = map {my $r = Route::Node::get($_); $r ? $r : ()} (@localcalls, @remotecalls);
	
	send_route($self, \&pc19, scalar @nodes, @nodes);
	
	# get all the users connected on the above nodes and send them out
	foreach $n (@nodes) {
		send_route($self, \&pc16, 1, $n, map {my $r = Route::User::get($_); $r ? ($r) : ()} $n->users);
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
		dbg('chan', "PCPROT: Trying to route back to source, dropped");
		return;
	}

	# always send it down the local interface if available
	my $dxchan = DXChannel->get($call);
	unless ($dxchan) {
		my $cl = Route::Node::get($call);
		$dxchan = $cl->dxchan if $cl;
		if (ref $dxchan) {
			if (ref $self && $dxchan eq $self) {
				dbg('chan', "PCPROT: Trying to route back to source, dropped");
				return;
			}
		}
	}
	if ($dxchan) {
		my $routeit = adjust_hops($dxchan, $line);   # adjust its hop count by node name
		if ($routeit) {
			$dxchan->send($routeit);
		}
	} else {
		dbg('chan', "PCPROT: No route available, dropped");
	}
}

# broadcast a message to all clusters taking into account isolation
# [except those mentioned after buffer]
sub broadcast_ak1a
{
	my $s = shift;				# the line to be rebroadcast
	my @except = @_;			# to all channels EXCEPT these (dxchannel refs)
	my @dxchan = DXChannel::get_all_nodes();
	my $dxchan;
	
	# send it if it isn't the except list and isn't isolated and still has a hop count
	foreach $dxchan (@dxchan) {
		next if grep $dxchan == $_, @except;
		next if $dxchan == $me;
		
		my $routeit = adjust_hops($dxchan, $s);      # adjust its hop count by node name
		$dxchan->send($routeit) unless $dxchan->{isolate} || !$routeit;
	}
}

# broadcast a message to all clusters ignoring isolation
# [except those mentioned after buffer]
sub broadcast_all_ak1a
{
	my $s = shift;				# the line to be rebroadcast
	my @except = @_;			# to all channels EXCEPT these (dxchannel refs)
	my @dxchan = DXChannel::get_all_nodes();
	my $dxchan;
	
	# send it if it isn't the except list and isn't isolated and still has a hop count
	foreach $dxchan (@dxchan) {
		next if grep $dxchan == $_, @except;
		next if $dxchan == $me;

		my $routeit = adjust_hops($dxchan, $s);      # adjust its hop count by node name
		$dxchan->send($routeit);
	}
}

# broadcast to all users
# storing the spot or whatever until it is in a state to receive it
sub broadcast_users
{
	my $s = shift;				# the line to be rebroadcast
	my $sort = shift;           # the type of transmission
	my $fref = shift;           # a reference to an object to filter on
	my @except = @_;			# to all channels EXCEPT these (dxchannel refs)
	my @dxchan = DXChannel::get_all_users();
	my $dxchan;
	my @out;
	
	foreach $dxchan (@dxchan) {
		next if grep $dxchan == $_, @except;
		push @out, $dxchan;
	}
	broadcast_list($s, $sort, $fref, @out);
}

# broadcast to a list of users
sub broadcast_list
{
	my $s = shift;
	my $sort = shift;
	my $fref = shift;
	my $dxchan;
	
	foreach $dxchan (@_) {
		my $filter = 1;
		next if $dxchan == $me;
		
		if ($sort eq 'dx') {
		    next unless $dxchan->{dx};
			($filter) = $dxchan->{spotsfilter}->it(@{$fref}) if ref $fref;
			next unless $filter;
		}
		next if $sort eq 'ann' && !$dxchan->{ann};
		next if $sort eq 'wwv' && !$dxchan->{wwv};
		next if $sort eq 'wcy' && !$dxchan->{wcy};
		next if $sort eq 'wx' && !$dxchan->{wx};

		$s =~ s/\a//og unless $dxchan->{beep};

		if ($dxchan->{state} eq 'prompt' || $dxchan->{state} eq 'talk') {
			$dxchan->send($s);	
		} else {
			$dxchan->delay($s);
		}
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

	unless ($pc39flag && $pc39flag == 1) {
		$self->send_now("D", DXProt::pc39($main::mycall, $self->msg('disc1', "System Op")));
	}

	# do routing stuff
#	my $node = Route::Node::get($self->{call});
#	my @rout = $node->del_nodes if $node;
	my @rout = $main::routeroot->del_node($call);
	dbg('route', "B/C PC21 (from PC39) for: " . join(',', (map{ $_->call } @rout))) if @rout;
	
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
	my ($self, $from, $to, $via, $line) = @_;
	
	$line =~ s/\^/\\5E/g;			# remove any ^ characters
	$self->send(DXProt::pc10($from, $to, $via, $line));
	Log('talk', $self->call, $from, $via?$via:$main::mycall, $line);
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
	
	if ($self->{routefilter}) {
		for (; @_ && $no; $no--) {
			my $r = shift;
			($filter, $hops) = $self->{routefilter}->it($self->{call}, $self->{dxcc}, $self->{itu}, $self->{cq}, $r->call, $r->dxcc, $r->itu, $r->cq);
			push @rin, $r if $filter;
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
			$self->send($routeit) unless $self->{isolate} || $self->{isolate};
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
	
	foreach $dxchan (@dxchan) {
		next if $dxchan == $self;
		next if $dxchan == $me;
		$dxchan->send_route($generate, @_);
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

1;
__END__ 
