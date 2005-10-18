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
use Investigate;
use RouteDB;
use Thingy;
use Thingy::Dx;
use Thingy::Rt;
use Thingy::Ping;
use Thingy::T;
use Thingy::Hello;
use Thingy::Bye;

use strict;

use vars qw($VERSION $BRANCH);

main::mkver($VERSION = q$Revision$);

use vars qw($pc11_max_age $pc23_max_age $last_pc50 $eph_restime $eph_info_restime $eph_pc34_restime
			$last_hour $last10 %eph  %pings %rcmds $ann_to_talk
			$pingint $obscount %pc19list $chatdupeage $chatimportfn
			$investigation_int $pc19_version $myprot_version
			%nodehops $baddx $badspotter $badnode $censorpc $rspfcheck
			$allowzero $decode_dk0wcy $send_opernam @checklist);

$pc11_max_age = 1*3600;			# the maximum age for an incoming 'real-time' pc11
$pc23_max_age = 1*3600;			# the maximum age for an incoming 'real-time' pc23

$last_hour = time;				# last time I did an hourly periodic update
%pings = ();                    # outstanding ping requests outbound
%rcmds = ();                    # outstanding rcmd requests outbound
%nodehops = ();                 # node specific hop control
%pc19list = ();					# list of outstanding PC19s that haven't had PC16s on them

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
$pingint = 5*60;
$obscount = 2;
$chatdupeage = 20 * 60 * 60;
$chatimportfn = "$main::root/chat_import";
$investigation_int = 12*60*60;	# time between checks to see if we can see this node
$pc19_version = 5466;			# the visible version no for outgoing PC19s generated from pc59

@checklist = 
(
 [ qw(i c c m bp bc c) ],			# pc10
 [ qw(i f m d t m c c h) ],		# pc11
 [ qw(i c bm m bm bm p h) ],		# pc12
 [ qw(i c h) ],					# 
 [ qw(i c h) ],					# 
 [ qw(i c m h) ],					# 
 undef ,						# pc16 has to be validated manually
 [ qw(i c c h) ],					# pc17
 [ qw(i m n) ],					# pc18
 undef ,						# pc19 has to be validated manually
 undef ,						# pc20 no validation
 [ qw(i c m h) ],					# pc21
 undef ,						# pc22 no validation
 [ qw(i d n n n n m c c h) ],		# pc23
 [ qw(i c p h) ],					# pc24
 [ qw(i c c n n) ],				# pc25
 [ qw(i f m d t m c c bc) ],		# pc26
 [ qw(i d n n n n m c c bc) ],	# pc27
 [ qw(i c c m c d t p m bp n p bp bc) ], # pc28
 [ qw(i c c n m) ],				# pc29
 [ qw(i c c n) ],					# pc30
 [ qw(i c c n) ],					# pc31
 [ qw(i c c n) ],					# pc32
 [ qw(i c c n) ],					# pc33
 [ qw(i c c m) ],					# pc34
 [ qw(i c c m) ],					# pc35
 [ qw(i c c m) ],					# pc36
 [ qw(i c c n m) ],				# pc37
 undef,							# pc38 not interested
 [ qw(i c m) ],					# pc39
 [ qw(i c c m p n) ],				# pc40
 [ qw(i c n m h) ],				# pc41
 [ qw(i c c n) ],					# pc42
 undef,							# pc43 don't handle it
 [ qw(i c c n m m c) ],			# pc44
 [ qw(i c c n m) ],				# pc45
 [ qw(i c c n) ],					# pc46
 undef,							# pc47
 undef,							# pc48
 [ qw(i c m h) ],					# pc49
 [ qw(i c n h) ],					# pc50
 [ qw(i c c n) ],					# pc51
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
 [ qw(i d n n n n n n m m m c c h) ],	# pc73
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
 [ qw(i c c c m) ],				# pc84
 [ qw(i c c c m) ],				# pc85
 undef,
 undef,
 undef,
 undef,
 [ qw(i c n) ],					# pc90
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
	for ($i = 1; $i < @$ref; $i++) {
		my ($blank, $act) = $$ref[$i] =~ /^(b?)(\w)$/;
		return 0 unless $act;
		next if $blank && $_[$i] =~ /^[ \*]$/;
		if ($act eq 'c') {
			return $i unless is_callsign($_[$i]);
		} elsif ($act eq 'i') {			
			;					# do nothing
		} elsif ($act eq 'm') {
			return $i unless is_pctext($_[$i]);
		} elsif ($act eq 'p') {
			return $i unless is_pcflag($_[$i]);
		} elsif ($act eq 'f') {
			return $i unless is_freq($_[$i]);
		} elsif ($act eq 'n') {
			return $i unless $_[$i] =~ /^[\d ]+$/;
		} elsif ($act eq 'h') {
			return $i unless $_[$i] =~ /^H\d\d?$/;
		} elsif ($act eq 'd') {
			return $i unless $_[$i] =~ /^\s*\d+-\w\w\w-[12][90]\d\d$/;
		} elsif ($act eq 't') {
			return $i unless $_[$i] =~ /^[012]\d[012345]\dZ$/;
		} 
	}
	return 0;
}

sub init
{
	do "$main::data/hop_table.pl" if -e "$main::data/hop_table.pl";
	confess $@ if $@;

	my $user = DXUser->get($main::mycall);
	die "User $main::mycall not setup or disappeared RTFM" unless $user;
	
	$main::me = DXProt->new($main::mycall, 0, $user); 
	$main::me->{here} = 1;
	$main::me->{state} = "indifferent";
	$main::me->{sort} = 'S';    # S for spider
	$main::me->{priv} = 9;
	$main::me->{metric} = 0;
	$main::me->{pingave} = 0;
	$main::me->{registered} = 1;
	$main::me->{version} = $myprot_version + int ($main::version * 100);
	$main::me->{build} = $main::build;
	$main::me->{lastcf} = $main::me->{lasthello} = time;
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
	$main::routeroot->add($call, '5000', 1) if $call ne $main::mycall;
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
	$ping = $pingint unless defined $ping;
	$self->{pingint} = $ping;
	$self->{nopings} = $user->nopings || $obscount;
	$self->{pingtime} = [ ];
	$self->{pingave} = 999;
	$self->{metric} ||= 100;
	$self->{lastping} = $main::systime;

	# send initialisation string
	unless ($self->{outbound}) {
		$self->sendinit;
	}
	
	$self->state('init');
	$self->{pc50_t} = $main::systime;

	# ALWAYS output the hello
	my $thing = Thingy::Hello->new(user => $call, h => $self->{here});
	$thing->broadcast($self);
	$self->lasthello($main::systime);
	
	# send info to all logged in thingies
	$self->tell_login('loginn');

	# run a script send the output to the debug file
	my $script = new Script(lc $call) || new Script('node_default');
	$script->run($self) if $script;
}

#
# send outgoing 'challenge'
#

sub sendinit
{
	my $self = shift;
	$self->send(pc18());
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
	unless (defined $pcno && $pcno >= 10 && $pcno <= 99) {
		dbg("PCPROT: unknown protocol") if isdbg('chanerr');
		return;
	}

	# check for and dump bad protocol messages
	my $n = check($pcno, @field);
	if ($n) {
		dbg("PCPROT: bad field $n, dumped (" . parray($checklist[$pcno-10]) . ")") if isdbg('chanerr');
		return;
	}

	# decrement any hop fields at this point
	if ($line =~ /\^H(\d\d?)\^?~?$/) {
		my $hops = $1 - 1;
		if ($hops < 0) {
			dbg("PCPROT: zero hop count, dumped") if isdbg('chanerr');
			return;
		}
		$line =~ s/\^H\d\d?(\^?~?)$/^H$hops$1/;
	}

	my $origin = $self->{call};
	no strict 'subs';
	my $sub = "handle_$pcno";

	if ($self->can($sub)) {
		$self->$sub($pcno, $line, $origin, @field);
	} else {
		$self->handle_default($pcno, $line, $origin, @field);
	}
}
	
# incoming talk commands
sub handle_10
{
	my $self = shift;
	my $pcno = shift;
	my $line = shift;
	my $origin = shift;

	# rsfp check
	return if $rspfcheck and !$self->rspfcheck(0, $_[6], $_[1]);
			
	# will we allow it at all?
	if ($censorpc) {
		my @bad;
		if (@bad = BadWords::check($_[3])) {
			dbg("PCPROT: Bad words: @bad, dropped") if isdbg('chanerr');
			return;
		}
	}

	# is it for me or one of mine?
	my ($from, $to, $via, $call, $dxchan);
	$from = $_[1];
	if ($_[5] gt ' ') {
		$via = $_[2];
		$to = $_[5];
	} else {
		$to = $_[2];
	}

	# if this is a 'nodx' node then ignore it
	if ($badnode->in($_[6]) || ($via && $badnode->in($via))) {
		dbg("PCPROT: Bad Node, dropped") if isdbg('chanerr');
		return;
	}

	# if this is a 'bad spotter' user then ignore it
	my $nossid = $from;
	$nossid =~ s/-\d+$//;
	if ($badspotter->in($nossid)) {
		dbg("PCPROT: Bad Spotter, dropped") if isdbg('chanerr');
		return;
	}

	# if we are converting announces to talk is it a dup?
	if ($ann_to_talk) {
		if (AnnTalk::is_talk_candidate($from, $_[3]) && AnnTalk::dup($from, $to, $_[3])) {
			dbg("DXPROT: Dupe talk from announce, dropped") if isdbg('chanerr');
			return;
		}
	}

	# remember a route to this node and also the node on which this user is
	RouteDB::update($_[6], $origin);
#	RouteDB::update($to, $_[6]);

	# it is here and logged on
	$dxchan = DXChannel::get($main::myalias) if $to eq $main::mycall;
	$dxchan = DXChannel::get($to) unless $dxchan;
	if ($dxchan && $dxchan->is_user) {
		$_[3] =~ s/\%5E/^/g;
		$dxchan->talk($from, $to, $via, $_[3]);
		return;
	}

	# is it elsewhere, visible on the cluster via the to address?
	# note: this discards the via unless the to address is on
	# the via address
	my ($ref, $vref);
	if ($ref = Route::get($to)) {
		$vref = Route::Node::get($via) if $via;
		$vref = undef unless $vref && grep $to eq $_, $vref->users;
		$ref->dxchan->talk($from, $to, $vref ? $via : undef, $_[3], $_[6]);
		return;
	}

	# can we see an interface to send it down?
	
	# not visible here, send a message of condolence
	$vref = undef;
	$ref = Route::get($from);
	$vref = $ref = Route::Node::get($_[6]) unless $ref; 
	if ($ref) {
		$dxchan = $ref->dxchan;
		$dxchan->talk($main::mycall, $from, $vref ? $vref->call : undef, $dxchan->msg('talknh', $to) );
	}
}

# DX Spot handling
sub handle_11
{
	my $self = shift;
	my $pcno = shift;
	my $line = shift;
	my $origin = shift;

	# route 'foreign' pc26s 
	if ($pcno == 26) {
		if ($_[7] ne $main::mycall) {
			$self->route($_[7], $line);
			return;
		}
	}
			
	# rsfp check
	#			return if $rspfcheck and !$self->rspfcheck(1, $_[7], $_[6]);

	# if this is a 'nodx' node then ignore it
	if ($badnode->in($_[7])) {
		dbg("PCPROT: Bad Node, dropped") if isdbg('chanerr');
		return;
	}
			
	# if this is a 'bad spotter' user then ignore it
	my $nossid = $_[6];
	$nossid =~ s/-\d+$//;
	if ($badspotter->in($nossid)) {
		dbg("PCPROT: Bad Spotter, dropped") if isdbg('chanerr');
		return;
	}
			
	# convert the date to a unix date
	my $d = cltounix($_[3], $_[4]);
	# bang out (and don't pass on) if date is invalid or the spot is too old (or too young)
	if (!$d || ($pcno == 11 && ($d < $main::systime - $pc11_max_age || $d > $main::systime + 900))) {
		dbg("PCPROT: Spot ignored, invalid date or out of range ($_[3] $_[4])\n") if isdbg('chanerr');
		return;
	}

	# is it 'baddx'
	if ($baddx->in($_[2]) || BadWords::check($_[2])) {
		dbg("PCPROT: Bad DX spot, ignored") if isdbg('chanerr');
		return;
	}
			
	# do some de-duping
	$_[5] =~ s/^\s+//;			# take any leading blanks off
	$_[2] = unpad($_[2]);		# take off leading and trailing blanks from spotted callsign
	if ($_[2] =~ /BUST\w*$/) {
		dbg("PCPROT: useless 'BUSTED' spot") if isdbg('chanerr');
		return;
	}
	if ($censorpc) {
		my @bad;
		if (@bad = BadWords::check($_[5])) {
			dbg("PCPROT: Bad words: @bad, dropped") if isdbg('chanerr');
			return;
		}
	}

	# remember a route
#	RouteDB::update($_[7], $self->{call});
#	RouteDB::update($_[6], $_[7]);
	
	my @spot = Spot::prepare($_[1], $_[2], $d, $_[5], $_[6], $_[7]);

	my $thing = Thingy::Dx->new(origin=>$main::mycall);
	$thing->from_DXProt(DXProt=>$line,spotdata=>\@spot);
	$thing->process($self);

	# this goes after the input filtering, but before the add
	# so that if it is input filtered, it isn't added to the dup
	# list. This allows it to come in from a "legitimate" source
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
				if ($to ne $_[7]) {
					$to = $_[7];
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
}
		
# announces
sub handle_12
{
	my $self = shift;
	my $pcno = shift;
	my $line = shift;
	my $origin = shift;

	#			return if $rspfcheck and !$self->rspfcheck(1, $_[5], $_[1]);

	# announce duplicate checking
	$_[3] =~ s/^\s+//;			# remove leading blanks

	if ($censorpc) {
		my @bad;
		if (@bad = BadWords::check($_[3])) {
			dbg("PCPROT: Bad words: @bad, dropped") if isdbg('chanerr');
			return;
		}
	}

	# if this is a 'nodx' node then ignore it
	if ($badnode->in($_[5])) {
		dbg("PCPROT: Bad Node, dropped") if isdbg('chanerr');
		return;
	}

	# if this is a 'bad spotter' user then ignore it
	my $nossid = $_[1];
	$nossid =~ s/-\d+$//;
	if ($badspotter->in($nossid)) {
		dbg("PCPROT: Bad Spotter, dropped") if isdbg('chanerr');
		return;
	}


	my $dxchan;
	
	if ((($dxchan = DXChannel::get($_[2])) && $dxchan->is_user) || $_[4] =~ /^[\#\w.]+$/){
		$self->send_chat($line, @_[1..6]);
	} elsif ($_[2] eq '*' || $_[2] eq $main::mycall) {

		# remember a route
#		RouteDB::update($_[5], $self->{call});
#		RouteDB::update($_[1], $_[5]);

		# ignore something that looks like a chat line coming in with sysop
		# flag - this is a kludge...
		if ($_[3] =~ /^\#\d+ / && $_[4] eq '*') {
			dbg('PCPROT: Probable chat rewrite, dropped') if isdbg('chanerr');
			return;
		}

		# here's a bit of fun, convert incoming ann with a callsign in the first word
		# or one saying 'to <call>' to a talk if we can route to the recipient
		if ($ann_to_talk) {
			my $call = AnnTalk::is_talk_candidate($_[1], $_[3]);
			if ($call) {
				my $ref = Route::get($call);
				if ($ref) {
					$dxchan = $ref->dxchan;
					$dxchan->talk($_[1], $call, undef, $_[3], $_[5]) if $dxchan != $self;
					return;
				}
			}
		}
	
		# send it
		$self->send_announce($line, @_[1..6]);
	} else {
		$self->route($_[2], $line);
	}
}
		
# incoming user		
sub handle_16
{
	my $self = shift;
	my $pcno = shift;
	my $line = shift;
	my $origin = shift;

	# general checks
	my $dxchan;
	my $ncall = $_[1];
	my $newline = "PC16^";
			
	# dos I want users from this channel?
	unless ($self->user->wantpc16) {
		dbg("PCPROT: don't send users to $origin") if isdbg('chanerr');
		return;
	}
	# is it me?
	if ($ncall eq $main::mycall) {
		dbg("PCPROT: trying to alter config on this node from outside!") if isdbg('chanerr');
		return;
	}

	RouteDB::update($ncall, $self->{call});

	# do we believe this call? 
#	unless ($ncall eq $self->{call} || $self->is_believed($ncall)) {
#		if (my $ivp = Investigate::get($ncall, $self->{call})) {
#			$ivp->store_pcxx($pcno,$line,$origin,@_);
#		} else {
#			dbg("PCPROT: We don't believe $ncall on $self->{call}") if isdbg('chanerr');
#		}
#		return;
#	}

	if (eph_dup($line)) {
		dbg("PCPROT: dup PC16 detected") if isdbg('chanerr');
		return;
	}

	my $parent = Route::Node::get($ncall); 

	# if there is a parent, proceed, otherwise if there is a latent PC19 in the PC19list, 
	# fix it up in the routing tables and issue it forth before the PC16
	if ($parent) {
		$dxchan = $parent->dxchan;
		if ($dxchan && $dxchan ne $self) {
			dbg("PCPROT: PC16 from $self->{call} trying to alter locally connected $ncall, ignored!") if isdbg('chanerr');
			return;
		}

		# input filter if required
		return unless $self->in_filter_route($parent);
	} else {
		dbg("PCPROT: Node $ncall not in config") if isdbg('chanerr');
		return;
	}

	# is he under the control of the new protocol?
#	if ($parent && $parent->np) {
#		dbg("PCPROT: $ncall aranea node, ignored") if isdbg('chanerr');
#		return;
#	}
		
	my $i;
	my @rout;
	for ($i = 2; $i < $#_; $i++) {
		my ($call, $conf, $here) = $_[$i] =~ /^(\S+) (\S) (\d)/o;
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
		my $flags = $here;
		
		if ($r) {
			my $au = $r->addparent($parent);					
			if ($r->flags != $flags) {
				$r->flags($flags);
				$au = $r;
			}
			push @rout, $r if $au;
		} else {
			push @rout, $parent->add_user($call, $flags);
		}
		
		
		# add this station to the user database, if required
		$call =~ s/-\d+$//o;	# remove ssid for users
		my $user = DXUser->get_current($call);
		$user = DXUser->new($call) if !$user;
		$user->homenode($parent->call) if !$user->homenode;
		$user->node($parent->call);
		$user->lastin($main::systime) unless DXChannel::get($call);
		$user->put;
	}
	$self->route_pc16($origin, $line, $parent, @rout) if @rout && (DXChannel::get($parent->call) || $parent->np);
}
		
# remove a user
sub handle_17
{
	my $self = shift;
	my $pcno = shift;
	my $line = shift;
	my $origin = shift;
	my $dxchan;
	my $ncall = $_[2];
	my $ucall = $_[1];

	eph_del_regex("^PC16\\^$ncall.*$ucall");
			
	# do I want users from this channel?
	unless ($self->user->wantpc16) {
		dbg("PCPROT: don't send users to $self->{call}") if isdbg('chanerr');
		return;
	}
	if ($ncall eq $main::mycall) {
		dbg("PCPROT: trying to alter config on this node from outside!") if isdbg('chanerr');
		return;
	}

	RouteDB::delete($ncall, $self->{call});

	# do we believe this call? 
#	unless ($ncall eq $self->{call} || $self->is_believed($ncall)) {
#		if (my $ivp = Investigate::get($ncall, $self->{call})) {
#			$ivp->store_pcxx($pcno,$line,$origin,@_);
#		} else {
#			dbg("PCPROT: We don't believe $ncall on $self->{call}") if isdbg('chanerr');
#		}
#		return;
#	}

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

	# is he under the control of the new protocol?
#	if ($parent && $parent->np) {
#		dbg("PCPROT: $ncall aranea node, ignored") if isdbg('chanerr');
#		return;
#	}

	# input filter if required and then remove user if present
	if ($parent && !$parent->np) {
#		return unless $self->in_filter_route($parent);	
		$parent->del_user($uref) if $uref;
	} 

	if (eph_dup($line)) {
		dbg("PCPROT: dup PC17 detected") if isdbg('chanerr');
		return;
	}

	$self->route_pc17($origin, $line, $parent, $uref) if (DXChannel::get($parent->call) || $parent->np);
}
		
# link request
sub handle_18
{
	my $self = shift;
	my $pcno = shift;
	my $line = shift;
	my $origin = shift;
	$self->state('init');	

	# record the type and version offered
	if ($_[1] =~ /DXSpider Version: (\d+\.\d+) Build: (\d+\.\d+)/) {
		$self->version(0 + $1);
		$self->user->version(0 + $1);
		$self->build(0 + $2);
		$self->user->build(0 + $2);
		unless ($self->is_spider) {
			$self->user->sort('S');
			$self->user->put;
			$self->sort('S');
		}
	} else {
		$self->version(50.0);
		$self->version($_[2] / 100) if $_[2] && $_[2] =~ /^\d+$/;
		$self->user->version($self->version);
	}

	# first clear out any nodes on this dxchannel
	my $parent = Route::Node::get($origin);
	my @rout = $parent->del_nodes;
	$self->route_pc21($origin, $line, @rout, $parent) if @rout;
	$self->send_local_config();
	$self->send(pc20());
}
		
# incoming cluster list
sub handle_19
{
	my $self = shift;
	my $pcno = shift;
	my $line = shift;
	my $origin = shift;

	my $i;
	my $newline = "PC19^";

	# new routing list
	my @rout;

	# first get the INTERFACE node
	my $parent = Route::Node::get($origin);
	unless ($parent) {
		dbg("DXPROT: my parent $origin has disappeared");
		$self->disconnect;
		return;
	}

	# parse the PC19
	for ($i = 1; $i < $#_-1; $i += 4) {
		my $here = $_[$i];
		my $call = uc $_[$i+1];
		my $conf = $_[$i+2];
		my $ver = $_[$i+3];
		next unless defined $here && defined $conf && is_callsign($call);

		eph_del_regex("^PC(?:21\\^$call|17\\^[^\\^]+\\^$call)");
				
		# check for sane parameters
		#				$ver = 5000 if $ver eq '0000';
		next unless $ver > 5000;	# only works with version 5 software that isn't a passive node
		next if length $call < 3; # min 3 letter callsigns
		next if $call eq $main::mycall;

		# check that this PC19 isn't trying to alter the wrong dxchan
		my $dxchan = DXChannel::get($call);
		if ($dxchan && $dxchan != $self) {
			dbg("PCPROT: PC19 from $origin trying to alter wrong locally connected $call, ignored!") if isdbg('chanerr');
			next;
		}

		# add this station to the user database, if required (don't remove SSID from nodes)
		my $user = DXUser->get_current($call);
		if (!$user) {
			$user = DXUser->new($call);
			$user->priv(1);		# I have relented and defaulted nodes
			$user->lockout(1);
			$user->homenode($call);
			$user->node($call);
		}
		$user->sort('A') unless $user->is_node;

		RouteDB::update($call, $origin);

		my $genline = "PC19^$here^$call^$conf^$ver^$_[-1]^"; 
		if (eph_dup($genline)) {
			dbg("PCPROT: dup PC19 for $call detected") if isdbg('chanerr');
			next;
		}

		my $r = Route::Node::get($call);
		my $flags = $here;

		# is he under the control of the new protocol and not my interface call?
		if ($call ne $origin && $r && $r->np) {
			dbg("PCPROT: $call aranea node, ignored") if isdbg('chanerr');
			next;
		}
		# modify the routing table if it is in it, otherwise store it in the pc19list for now
		if ($r) {
			my $ar;
			if ($call ne $parent->call) {
				if ($self->in_filter_route($r)) {
					$ar = $parent->add($call, $ver, $flags);
					push @rout, $ar if $ar;
				} else {
					next;
				}
			} else {
				if ($r->version != $ver || $r->flags != $flags) {
					$r->version($ver);
					$r->flags($flags);
					push @rout, $r;
				}
			}
		} else {

			# if he is directly connected or allowed then add him, otherwise store him up for later
			if ($call eq $origin || $user->wantroutepc19) {
				my $new = Route->new($call); # throw away
				if ($self->in_filter_route($new)) {
					my $ar = $parent->add($call, $ver, $flags);
					$user->wantroutepc19(1) unless defined $user->wantroutepc19;
					push @rout, $ar if $ar;
				} else {
					next;
				}
			}
		}

		# unbusy and stop and outgoing mail (ie if somehow we receive another PC19 without a disconnect)
		my $mref = DXMsg::get_busy($call);
		$mref->stop_msg($call) if $mref;
				
		$user->lastin($main::systime) unless DXChannel::get($call);
		$user->put;
	}

	# we only output information that we regard as reliable
	@rout = grep {$_ && (DXChannel::get($_->{call}) || $_->np) } @rout;
	$self->route_pc19($origin, $line, @rout) if @rout;
}
		
# send local configuration
sub handle_20
{
	my $self = shift;
	my $pcno = shift;
	my $line = shift;
	my $origin = shift;
	$self->send_local_config();
	$self->send(pc22());
	$self->state('normal');
	$self->{lastping} = 0;
	my $thing = Thingy::Rt->new(user=>$self->{call});
	my $nref = Route::Node::get($self->{call});
	$thing->copy_pc16_data($nref);
	$thing->broadcast($self);
	$self->lastcf($main::systime);
}
		
# delete a cluster from the list
sub handle_21
{
	my $self = shift;
	my $pcno = shift;
	my $line = shift;
	my $origin = shift;
	my $call = uc $_[1];

	eph_del_regex("^PC1[679].*$call");
			
	# if I get a PC21 from the same callsign as self then treat it
	# as a PC39: I have gone away
	if ($call eq $self->call) {
		$self->disconnect(1);
		return;
	}

	RouteDB::delete($call, $origin);

	# check if we believe this
#	unless ($call eq $origin || $self->is_believed($call)) {
#		if (my $ivp = Investigate::get($call, $origin)) {
#			$ivp->store_pcxx($pcno,$line,$origin,@_);
#		} else {
#			dbg("PCPROT: We don't believe $call on $origin") if isdbg('chanerr');
#		}
#		return;
#	}

	# check to see if we are in the pc19list, if we are then don't bother with any of
	# this routing table manipulation, just remove it from the list and dump it
	my @rout;

	my $parent = Route::Node::get($origin);
	unless ($parent) {
		dbg("DXPROT: my parent $origin has disappeared");
		$self->disconnect;
		return;
	}
	if ($call ne $main::mycall) { # don't allow malicious buggers to disconnect me!
		my $node = Route::Node::get($call);
		if ($node) {
			
			my $dxchan = DXChannel::get($call);
			if ($dxchan && $dxchan != $self) {
				dbg("PCPROT: PC21 from $origin trying to alter locally connected $call, ignored!") if isdbg('chanerr');
				return;
			}
			
			# input filter it
			return unless $self->in_filter_route($node);
			
			# is he under the control of the new protocol?
			if ($node->np) {
				dbg("PCPROT: $call aranea node, ignored") if isdbg('chanerr');
				return;
			}
			
			# routing objects
			push @rout, $node->del($parent);
		}
	} else {
		dbg("PCPROT: I WILL _NOT_ be disconnected!") if isdbg('chanerr');
		return;
	}

	@rout = grep {$_ && (DXChannel::get($_->{call}) || $_->np) } @rout;
	$self->route_pc21($origin, $line, @rout) if @rout;
}
		

sub handle_22
{
	my $self = shift;
	my $pcno = shift;
	my $line = shift;
	my $origin = shift;
	$self->state('normal');
	$self->{lastping} = 0;
	my $thing = Thingy::Rt->new(user=>$self->{call});
	my $nref = Route::Node::get($self->{call});
	$thing->copy_pc16_data($nref);
	$thing->broadcast($self);
	$self->lastcf($main::systime);
}
				
# WWV info
sub handle_23
{
	my $self = shift;
	my $pcno = shift;
	my $line = shift;
	my $origin = shift;
			
	# route foreign' pc27s 
	if ($pcno == 27) {
		if ($_[8] ne $main::mycall) {
			$self->route($_[8], $line);
			return;
		}
	}

	# only do a rspf check on PC23 (not 27)
	if ($pcno == 23) {
		return if $rspfcheck and !$self->rspfcheck(1, $_[8], $_[7])
	}

	# do some de-duping
	my $d = cltounix($_[1], sprintf("%02d18Z", $_[2]));
	my $sfi = unpad($_[3]);
	my $k = unpad($_[4]);
	my $i = unpad($_[5]);
	my ($r) = $_[6] =~ /R=(\d+)/;
	$r = 0 unless $r;
	if (($pcno == 23 && $d < $main::systime - $pc23_max_age) || $d > $main::systime + 1500 || $_[2] < 0 || $_[2] > 23) {
		dbg("PCPROT: WWV Date ($_[1] $_[2]) out of range") if isdbg('chanerr');
		return;
	}
	if (Geomag::dup($d,$sfi,$k,$i,$_[6])) {
		dbg("PCPROT: Dup WWV Spot ignored\n") if isdbg('chanerr');
		return;
	}
	$_[7] =~ s/-\d+$//o;		# remove spotter's ssid
		
	my $wwv = Geomag::update($d, $_[2], $sfi, $k, $i, @_[6..8], $r);

	my $rep;
	eval {
		$rep = Local::wwv($self, $_[1], $_[2], $sfi, $k, $i, @_[6..8], $r);
	};
	#			dbg("Local::wwv2 error $@") if isdbg('local') if $@;
	return if $rep;

	# DON'T be silly and send on PC27s!
	return if $pcno == 27;

	# broadcast to the eager world
	send_wwv_spot($self, $line, $d, $_[2], $sfi, $k, $i, @_[6..8]);
}
		
# set here status
sub handle_24
{
	my $self = shift;
	my $pcno = shift;
	my $line = shift;
	my $origin = shift;
	my $call = uc $_[1];
	my ($nref, $uref);
	$nref = Route::Node::get($call);
	$uref = Route::User::get($call);
	return unless $nref || $uref; # if we don't know where they are, it's pointless sending it on
			
	if (eph_dup($line)) {
		dbg("PCPROT: Dup PC24 ignored\n") if isdbg('chanerr');
		return;
	}
	
	$nref->here($_[2]) if $nref;
	$uref->here($_[2]) if $uref;
	my $ref = $nref || $uref;
	return unless $self->in_filter_route($ref);

	$self->route_pc24($origin, $line, $ref, $_[3]);
}
		
# merge request
sub handle_25
{
	my $self = shift;
	my $pcno = shift;
	my $line = shift;
	my $origin = shift;
	if ($_[1] ne $main::mycall) {
		$self->route($_[1], $line);
		return;
	}
	if ($_[2] eq $main::mycall) {
		dbg("PCPROT: Trying to merge to myself, ignored") if isdbg('chanerr');
		return;
	}

	Log('DXProt', "Merge request for $_[3] spots and $_[4] WWV from $_[2]");
			
	# spots
	if ($_[3] > 0) {
		my @in = reverse Spot::search(1, undef, undef, 0, $_[3]);
		my $in;
		foreach $in (@in) {
			$self->send(pc26(@{$in}[0..4], $_[2]));
		}
	}

	# wwv
	if ($_[4] > 0) {
		my @in = reverse Geomag::search(0, $_[4], time, 1);
		my $in;
		foreach $in (@in) {
			$self->send(pc27(@{$in}[0..5], $_[2]));
		}
	}
}

sub handle_26 {goto &handle_11}
sub handle_27 {goto &handle_23}

# mail/file handling
sub handle_28
{
	my $self = shift;
	my $pcno = shift;
	my $line = shift;
	my $origin = shift;
	if ($_[1] eq $main::mycall) {
		no strict 'refs';
		my $sub = "DXMsg::handle_$pcno";
		&$sub($self, @_);
	} else {
		$self->route($_[1], $line) unless $self->is_clx;
	}
}

sub handle_29 {goto &handle_28}
sub handle_30 {goto &handle_28}
sub handle_31 {goto &handle_28}
sub handle_32 {goto &handle_28}
sub handle_33 {goto &handle_28}
		
sub handle_34
{
	my $self = shift;
	my $pcno = shift;
	my $line = shift;
	my $origin = shift;
	if (eph_dup($line, $eph_pc34_restime)) {
		dbg("PCPROT: dupe PC34, ignored") if isdbg('chanerr');
	} else {
		$self->process_rcmd($_[1], $_[2], $_[2], $_[3]);
	}
}
		
# remote command replies
sub handle_35
{
	my $self = shift;
	my $pcno = shift;
	my $line = shift;
	my $origin = shift;
	eph_del_regex("^PC35\\^$_[2]\\^$_[1]\\^");
	$self->process_rcmd_reply($_[1], $_[2], $_[1], $_[3]);
}
		
sub handle_36 {goto &handle_34}

# database stuff
sub handle_37
{
	my $self = shift;
	my $pcno = shift;
	my $line = shift;
	my $origin = shift;
	if ($_[1] eq $main::mycall) {
		no strict 'refs';
		my $sub = "DXDb::handle_$pcno";
		&$sub($self, @_);
	} else {
		$self->route($_[1], $line) unless $self->is_clx;
	}
}

# node connected list from neighbour
sub handle_38
{
	my $self = shift;
	my $pcno = shift;
	my $line = shift;
	my $origin = shift;
}
		
# incoming disconnect
sub handle_39
{
	my $self = shift;
	my $pcno = shift;
	my $line = shift;
	my $origin = shift;
	if ($_[1] eq $origin) {
		$self->disconnect(1);
	} else {
		dbg("PCPROT: came in on wrong channel") if isdbg('chanerr');
	}
}

sub handle_40 {goto &handle_28}
		
# user info
sub handle_41
{
	my $self = shift;
	my $pcno = shift;
	my $line = shift;
	my $origin = shift;
	my $call = $_[1];

	my $l = $line;
	$l =~ s/[\x00-\x20\x7f-\xff]+//g; # remove all funny characters and spaces for dup checking
	if (eph_dup($l, $eph_info_restime)) {
		dbg("PCPROT: dup PC41, ignored") if isdbg('chanerr');
		return;
	}
			
	# input filter if required
	#			my $ref = Route::get($call) || Route->new($call);
	#			return unless $self->in_filter_route($ref);

	if ($_[3] eq $_[2] || $_[3] =~ /^\s*$/) {
		dbg('PCPROT: invalid value') if isdbg('chanerr');
		return;
	}

	# add this station to the user database, if required
	my $user = DXUser->get_current($call);
	$user = DXUser->new($call) unless $user;
			
	if ($_[2] == 1) {
		$user->name($_[3]);
	} elsif ($_[2] == 2) {
		$user->qth($_[3]);
	} elsif ($_[2] == 3) {
		if (is_latlong($_[3])) {
			my ($lat, $long) = DXBearing::stoll($_[3]);
			$user->lat($lat);
			$user->long($long);
			$user->qra(DXBearing::lltoqra($lat, $long));
		} else {
			dbg('PCPROT: not a valid lat/long') if isdbg('chanerr');
			return;
		}
	} elsif ($_[2] == 4) {
		$user->homenode($_[3]);
	} elsif ($_[2] == 5) {
		if (is_qra(uc $_[3])) {
			my ($lat, $long) = DXBearing::qratoll(uc $_[3]);
			$user->lat($lat);
			$user->long($long);
			$user->qra(uc $_[3]);
		} else {
			dbg('PCPROT: not a valid QRA locator') if isdbg('chanerr');
			return;
		}
	}
	$user->lastoper($main::systime); # to cut down on excessive for/opers being generated
	$user->put;

	unless ($self->{isolate}) {
		DXChannel::broadcast_nodes($line, $self); # send it to everyone but me
	}

	#  perhaps this IS what we want after all
	#			$self->route_pc41($ref, $call, $_[2], $_[3], $_[4]);
}

sub handle_42 {goto &handle_28}


# database
sub handle_44 {goto &handle_37}
sub handle_45 {goto &handle_37}
sub handle_46 {goto &handle_37}
sub handle_47 {goto &handle_37}
sub handle_48 {goto &handle_37}
		
# message and database
sub handle_49
{
	my $self = shift;
	my $pcno = shift;
	my $line = shift;
	my $origin = shift;

	if (eph_dup($line)) {
		dbg("PCPROT: Dup PC49 ignored\n") if isdbg('chanerr');
		return;
	}
	
	if ($_[1] eq $main::mycall) {
		DXMsg::handle_49($self, @_);
	} else {
		$self->route($_[1], $line) unless $self->is_clx;
	}
}

# keep alive/user list
sub handle_50
{
	my $self = shift;
	my $pcno = shift;
	my $line = shift;
	my $origin = shift;

	my $call = $_[1];

	RouteDB::update($call, $origin);

	my $node = Route::Node::get($call);
	if ($node) {
		return unless $node->call eq $origin;
		$node->usercount($_[2]);

		# input filter if required
		return unless $self->in_filter_route($node);

		$self->route_pc50($origin, $line, $node, $_[2], $_[3]) unless eph_dup($line);
	}
}
		
# incoming ping requests/answers
sub handle_51
{
	my $self = shift;
	my $pcno = shift;
	my $line = shift;
	my $origin = shift;

	if (eph_dup($line, 60)) {
		dbg("PCPROT: dup PC51 detected") if isdbg('chanerr');
		return;
	}

	my $thing = Thingy::Ping->new(origin=>$main::mycall);
	$thing->from_DXProt($self, $line, @_);
	$thing->handle($self);
}

# dunno but route it
sub handle_75
{
	my $self = shift;
	my $pcno = shift;
	my $line = shift;
	my $origin = shift;
	my $call = $_[1];
	if ($call ne $main::mycall) {
		$self->route($call, $line);
	}
}

# WCY broadcasts
sub handle_73
{
	my $self = shift;
	my $pcno = shift;
	my $line = shift;
	my $origin = shift;
	my $call = $_[1];
			
	# do some de-duping
	my $d = cltounix($call, sprintf("%02d18Z", $_[2]));
	if (($pcno == 23 && $d < $main::systime - $pc23_max_age) || $d > $main::systime + 1500 || $_[2] < 0 || $_[2] > 23) {
		dbg("PCPROT: WCY Date ($call $_[2]) out of range") if isdbg('chanerr');
		return;
	}
	@_ = map { unpad($_) } @_;
	if (WCY::dup($d)) {
		dbg("PCPROT: Dup WCY Spot ignored\n") if isdbg('chanerr');
		return;
	}
		
	my $wcy = WCY::update($d, @_[2..12]);

	my $rep;
	eval {
		$rep = Local::wcy($self, @_[1..12]);
	};
	# dbg("Local::wcy error $@") if isdbg('local') if $@;
	return if $rep;

	# broadcast to the eager world
	send_wcy_spot($self, $line, $d, @_[2..12]);
}

# remote commands (incoming)
sub handle_84
{
	my $self = shift;
	my $pcno = shift;
	my $line = shift;
	my $origin = shift;
	$self->process_rcmd($_[1], $_[2], $_[3], $_[4]);
}

# remote command replies
sub handle_85
{
	my $self = shift;
	my $pcno = shift;
	my $line = shift;
	my $origin = shift;
	$self->process_rcmd_reply($_[1], $_[2], $_[3], $_[4]);
}

# if get here then rebroadcast the thing with its Hop count decremented (if
# there is one). If it has a hop count and it decrements to zero then don't
# rebroadcast it.
#
# NOTE - don't arrive here UNLESS YOU WANT this lump of protocol to be
#        REBROADCAST!!!!
#

sub handle_default
{
	my $self = shift;
	my $pcno = shift;
	my $line = shift;
	my $origin = shift;

	if (eph_dup($line)) {
		dbg("PCPROT: Ephemeral dup, dropped") if isdbg('chanerr');
	} else {
		unless ($self->{isolate}) {
			DXChannel::broadcast_nodes($line, $self) if $line =~ /\^H\d+\^?~?$/; # send it to everyone but me
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
	my @dxchan = DXChannel::get_all();
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

#	Investigate::process();

	# every ten seconds
	if ($t - $last10 >= 10) {	
		# clean out ephemera 

		eph_clean();
		import_chat();
		

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
	my @dxchan = DXChannel::get_all();
	my $dxchan;
	my @dxcc = ((Prefix::cty_data($_[6]))[0..2], (Prefix::cty_data($_[7]))[0..2]);

	# send it if it isn't the except list and isn't isolated and still has a hop count
	# taking into account filtering and so on
	foreach $dxchan (@dxchan) {
		next if $dxchan == $main::me;
		next if $dxchan == $self && $self->is_node;
		my $routeit;
		my ($filter, $hops);

		$dxchan->wwv($line, $self->{isolate}, @_, $self->{call}, @dxcc);
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
	my @dxchan = DXChannel::get_all();
	my $dxchan;
	my @dxcc = ((Prefix::cty_data($_[10]))[0..2], (Prefix::cty_data($_[11]))[0..2]);
	
	# send it if it isn't the except list and isn't isolated and still has a hop count
	# taking into account filtering and so on
	foreach $dxchan (@dxchan) {
		next if $dxchan == $main::me;
		next if $dxchan == $self;

		$dxchan->wcy($line, $self->{isolate}, @_, $self->{call}, @dxcc);
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
	my @dxchan = DXChannel::get_all();
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
	my @a = Prefix::cty_data($_[0]);
	my @b = Prefix::cty_data($_[4]);
	if ($self->{inannfilter}) {
		my ($filter, $hops) = 
			$self->{inannfilter}->it(@_, $self->{call}, 
									 @a[0..2],
									 @b[0..2], $a[3], $b[3]);
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
		$dxchan->announce($line, $self->{isolate}, $to, $target, $text, @_, $self->{call},
						  @a[0..2], @b[0..2]);
	}
}

my $msgid = 0;

sub nextchatmsgid
{
	$msgid++;
	$msgid = 1 if $msgid > 999;
	return $msgid;
}

# send a chat line
sub send_chat
{
	my $self = shift;
	my $line = shift;
	my @dxchan = DXChannel::get_all();
	my $dxchan;
	my $target = $_[3];
	my $text = unpad($_[2]);
	my $ak1a_line;
				
	# munge the group and recast the line if required
	if ($target =~ s/\.LST$//) {
		$ak1a_line = $line;
	}
	
	# obtain country codes etc 
	my @a = Prefix::cty_data($_[0]);
	my @b = Prefix::cty_data($_[4]);
	if ($self->{inannfilter}) {
		my ($filter, $hops) = 
			$self->{inannfilter}->it(@_, $self->{call}, 
									 @a[0..2],
									 @b[0..2], $a[3], $b[3]);
		unless ($filter) {
			dbg("PCPROT: Rejected by input announce filter") if isdbg('chanerr');
			return;
		}
	}

	if (AnnTalk::dup($_[0], $_[1], $_[2], $chatdupeage)) {
		dbg("PCPROT: Duplicate Announce ignored") if isdbg('chanerr');
		return;
	}


	Log('chat', $target, $_[0], $text);

	# send it if it isn't the except list and isn't isolated and still has a hop count
	# taking into account filtering and so on
	foreach $dxchan (@dxchan) {
		my $is_ak1a = $dxchan->is_ak1a;
		
		if ($dxchan->is_node) {
			next if $dxchan == $main::me;
			next if $dxchan == $self;
			next unless $dxchan->is_spider || $is_ak1a;
			next if $target eq 'LOCAL';
			if (!$ak1a_line && $is_ak1a) {
				$ak1a_line = DXProt::pc12($_[0], $text, $_[1], "$target.LST");
			}
		}
		
		$dxchan->chat($is_ak1a ? $ak1a_line : $line, $self->{isolate}, $target, $_[1], 
					  $text, @_, $self->{call}, @a[0..2], @b[0..2]);
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

sub chat
{
	goto &announce;
}


sub send_local_config
{
	my $self = shift;
	my $node;
	my @nodes;
	my @localnodes;
	my @remotenodes;

	dbg('DXProt::send_local_config') if isdbg('trace');
	
	# send our nodes
	if ($self->{isolate}) {
		@localnodes = ( $main::routeroot );
		$self->send_route($main::mycall, \&pc19, 1, $main::routeroot);
	} else {
		# create a list of all the nodes that are not connected to this connection
		# and are not themselves isolated, this to make sure that isolated nodes
        # don't appear outside of this node

		# send locally connected nodes
		my @dxchan = grep { $_->call ne $main::mycall && $_ != $self && !$_->{isolate} && ($_->is_node || $_->is_aranea) } DXChannel::get_all();
		@localnodes = map { my $r = Route::Node::get($_->{call}); $r ? $r : () } @dxchan if @dxchan;
		$self->send_route($main::mycall, \&pc19, scalar(@localnodes)+1, $main::routeroot, @localnodes);

		my $node;
		my @rawintcalls = map { $_->nodes } @localnodes if @localnodes;
		my @intcalls;
		for $node (@rawintcalls) {
			push @intcalls, $node unless grep $node eq $_, @intcalls; 
		}
		my $ref = Route::Node::get($self->{call});
		my @rnodes = $ref->nodes;
		for $node (@intcalls) {
			push @remotenodes, Route::Node::get($node) unless grep $node eq $_, @rnodes, @remotenodes;
		}
		@remotenodes = grep {$_ && (DXChannel::get($_->{call}) || $_->np) } @remotenodes;
		$self->send_route($main::mycall, \&pc19, scalar(@remotenodes), @remotenodes);
	}
	
	# get all the users connected on the above nodes and send them out
	foreach $node ($main::routeroot, @localnodes, @remotenodes) {
		if ($node) {
			my @rout = map {my $r = Route::User::get($_); $r ? ($r) : ()} $node->users;
			$self->send_route($main::mycall, \&pc16, 1, $node, @rout) if @rout && $self->user->wantsendpc16;
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
	my $dxchan = DXChannel::get($call);
	if ($dxchan) {
		dbg("route: $call -> $dxchan->{call} direct" ) if isdbg('route');
	} else {
		my $cl = Route::get($call);
		$dxchan = $cl->dxchan if $cl;
		if (ref $dxchan) {
			if (ref $self && $dxchan eq $self) {
				dbg("PCPROT: Trying to route back to source, dropped") if isdbg('chanerr');
				return;
			}
			dbg("route: $call -> $dxchan->{call} using normal route" ) if isdbg('route');
		}
	}

	# try the backstop method
	unless ($dxchan) {
		my $rcall = RouteDB::get($call);
		if ($rcall) {
			if ($self && $rcall eq $self->{call}) {
				dbg("PCPROT: Trying to route back to source, dropped") if isdbg('chanerr');
				return;
			}
			$dxchan = DXChannel::get($rcall);
			dbg("route: $call -> $rcall using RouteDB" ) if isdbg('route') && $dxchan;
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
#			$hops--;               this is done on receipt now
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
	return ();
}


# add a ping request to the ping queues
sub addping
{
	my ($from, $to, $via) = @_;
	my $thing = Thingy::Ping->new_ping($from eq $main::mycall ? () : (user=>$from), $via ? (touser=> $to, group => $via) : (group => $to));
	$thing->remember;
	$thing->broadcast;
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
			my $dxchan = DXChannel::get($s->{call});
			my $ref = $user eq $tonode ? $dxchan : (DXChannel::get($user) || $dxchan);
			$ref->send($line) if $ref;
			delete $rcmds{$fromnode} if !$dxchan;
		} else {
			# send unsolicited ones to the sysop
			my $dxchan = DXChannel::get($main::myalias);
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

	# get rid of any PC16/17/19
	eph_del_regex("^PC1[679]*$call");

	# do routing stuff, remove me from routing table
	my $node = Route::Node::get($call);
	my @rout;
	if ($node) {
		@rout = $node->del($main::routeroot);
		
		# and all my ephemera as well
		for (@rout) {
			my $c = $_->call;
			eph_del_regex("^PC1[679].*$c");
		}
	}

	RouteDB::delete_interface($call);
	
	# remove them from the pc19list as well
	while (my ($k,$v) = each %pc19list) {
		my @l = grep {$_->[0] ne $call} @{$pc19list{$k}};
		if (@l) {
			$pc19list{$k} = \@l;
		} else {
			delete $pc19list{$k};
		}
		
		# and the ephemera
		eph_del_regex("^PC1[679].*$k");
	}

	# unbusy and stop and outgoing mail
	my $mref = DXMsg::get_busy($call);
	$mref->stop_msg($call) if $mref;
	
	# broadcast to all other nodes that all the nodes connected to via me are gone
	unless ($pc39flag && $pc39flag == 2) {
		my $thing = Thingy::Bye->new(user=>$call);
		$thing->broadcast($self);

		$self->route_pc21($main::mycall, undef, @rout) if @rout;
	}

	# remove outstanding pings
	Thingy::Ping::forget($call);
	
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
	my $origin = shift;
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
				($filter, $hops) = $self->{routefilter}->it($self->{call}, $self->{dxcc}, $self->{itu}, $self->{cq}, $r->call, $r->dxcc, $r->itu, $r->cq, $self->{state}, $r->{state});
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
	my $origin = shift;
	my $generate = shift;
	my $line = shift;
	my @dxchan = DXChannel::get_all_nodes();
	my $dxchan;
	
	unless ($self->{isolate}) {
		foreach $dxchan (@dxchan) {
			next if $dxchan == $self;
			next if $dxchan == $main::me;
			next unless $dxchan->isa('DXProt');
			next if ($generate == \&pc16 || $generate==\&pc17) && !$dxchan->user->wantsendpc16;
 
			$dxchan->send_route($origin, $generate, @_);
		}
	}
}

sub route_pc16
{
	my $self = shift;
	return unless $self->user->wantpc16;
	my $origin = shift;
	my $line = shift;
	broadcast_route($self, $origin, \&pc16, $line, 1, @_);
}

sub route_pc17
{
	my $self = shift;
	return unless $self->user->wantpc16;
	my $origin = shift;
	my $line = shift;
	broadcast_route($self, $origin, \&pc17, $line, 1, @_);
}

sub route_pc19
{
	my $self = shift;
	my $origin = shift;
	my $line = shift;
	broadcast_route($self, $origin, \&pc19, $line, scalar @_, @_);
}

sub route_pc21
{
	my $self = shift;
	my $origin = shift;
	my $line = shift;
	broadcast_route($self, $origin, \&pc21, $line, scalar @_, @_);
}

sub route_pc24
{
	my $self = shift;
	my $origin = shift;
	my $line = shift;
	broadcast_route($self, $origin, \&pc24, $line, 1, @_);
}

sub route_pc41
{
	my $self = shift;
	my $origin = shift;
	my $line = shift;
	broadcast_route($self, $origin, \&pc41, $line, 1, @_);
}

sub route_pc50
{
	my $self = shift;
	my $origin = shift;
	my $line = shift;
	broadcast_route($self, $origin, \&pc50, $line, 1, @_);
}

sub in_filter_route
{
	my $self = shift;
	my $r = shift;
	my ($filter, $hops) = (1, 1);
	
	if ($self->{inroutefilter}) {
		($filter, $hops) = $self->{inroutefilter}->it($self->{call}, $self->{dxcc}, $self->{itu}, $self->{cq}, $r->call, $r->dxcc, $r->itu, $r->cq, $self->state, $r->state);
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
	dbg("PCPROT: emphemeral duplicate") if $r && isdbg('chanerr'); 
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


# import any msgs in the chat directory
# the messages are sent to the chat group which forms the
# the first part of the name (eg: solar.1243.txt would be
# sent to chat group SOLAR)
# 
# Each message found is sent: one non-blank line to one chat
# message. So 4 lines = 4 chat messages.
# 
# The special name LOCAL is for local users ANN
# The special name ALL is for ANN/FULL
# The special name SYSOP is for ANN/SYSOP
#
sub import_chat
{
	# are there any to do in this directory?
	return unless -d $chatimportfn;
	unless (opendir(DIR, $chatimportfn)) {
		dbg("can\'t open $chatimportfn $!") if isdbg('msg');
		Log('msg', "can\'t open $chatimportfn $!");
		return;
	} 

	my @names = readdir(DIR);
	closedir(DIR);
	my $name;
	foreach $name (@names) {
		next if $name =~ /^\./;
		my $fn = "$chatimportfn/$name";
		next unless -f $fn;
		unless (open(MSG, $fn)) {
	 		dbg("can\'t open import file $fn $!") if isdbg('msg');
			Log('msg', "can\'t open import file $fn $!");
			unlink($fn);
			next;
		}
		my @msg = map { s/\r?\n$//; $_ } <MSG>;
		close(MSG);
		unlink($fn);

		my @cat = split /\./, $name;
		my $target = uc $cat[0];

		foreach my $text (@msg) {
			next unless $text && $text !~ /^\s*#/;
			if ($target eq 'ALL' || $target eq 'LOCAL' || $target eq 'SYSOP') {
				my $sysopflag = $target eq 'SYSOP' ? '*' : ' ';
				if ($target ne 'LOCAL') {
					send_announce($main::me, pc12($main::mycall, $text, '*', $sysopflag), $main::mycall, '*', $text, $sysopflag, $main::mycall, '0');
				} else {
					Log('ann', 'LOCAL', $main::mycall, $text);
					DXChannel::broadcast_list("To LOCAL de ${main::mycall}: $text\a", 'ann', undef, DXCommandmode->get_all());
				}
			} else {
				my $msgid = nextchatmsgid();
				$text = "#$msgid $text";
				send_chat($main::me, pc12($main::mycall, $text, '*', $target), $main::mycall, '*', $text, $target, $main::mycall, '0');
			}
		}
	}
}

1;
__END__ 
