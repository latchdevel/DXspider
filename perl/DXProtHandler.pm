#
# PC Protocol handlers
#
# This is still part of the DXProt package
# It has just been split off for convenience
#
#

use strict;

package DXProt;
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

use vars qw($VERSIONH $BRANCHH);
$VERSIONH = sprintf( "%d.%03d", q$Revision$ =~ /:\s+(\d+)\.(\d+)/ );
$BRANCHH = sprintf( "%d.%03d", q$Revision$ =~ /:\s+\d+\.\d+\.(\d+)\.(\d+)/ || (0,0));
$main::build += $VERSIONH;
$main::branch += $BRANCHH;

use vars qw($pc11_max_age $pc23_max_age $last_pc50 $eph_restime $eph_info_restime $eph_pc34_restime
			$last_hour $last10 %eph  %pings %rcmds $ann_to_talk $pc19_version
			$pingint $obscount %pc19list $chatdupeage $investigation_int
			%nodehops $baddx $badspotter $badnode $censorpc $rspfcheck $use_newroute
			$allowzero $decode_dk0wcy $send_opernam @checklist);

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

	# it is here and logged on
	$dxchan = DXChannel->get($main::myalias) if $to eq $main::mycall;
	$dxchan = DXChannel->get($to) unless $dxchan;
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
		$ref->bestdxchan->talk($from, $to, $vref ? $via : undef, $_[3], $_[6]);
		return;
	}

	# not visible here, send a message of condolence
	$vref = undef;
	$ref = Route::get($from);
	$vref = $ref = Route::Node::get($_[6]) unless $ref; 
	if ($ref) {
		$dxchan = $ref->bestdxchan;
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
	if ($baddx->in($_[2]) || BadWords::check($_[2]) || $_[2] =~ /COCK/) {
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


	my @spot = Spot::prepare($_[1], $_[2], $d, $_[5], $_[6], $_[7]);
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
	if (Spot::dup($_[1], $_[2], $d, $_[5], $_[6])) {
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
				my $dxchan = $node->bestdxchan;
				if ($dxchan && $dxchan->is_clx) {
					route(undef, $to, pc84($main::mycall, $to, $main::mycall, $cmd));
				} else {
					route(undef, $to, pc34($main::mycall, $to, $cmd));
				}
				if ($to ne $_[7]) {
					$to = $_[7];
					$node = Route::Node::get($to);
					if ($node) {
						$dxchan = $node->bestdxchan;
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
	
	if ((($dxchan = DXChannel->get($_[2])) && $dxchan->is_user) || $_[4] =~ /^[\#\w.]+$/){
		$self->send_chat($line, @_[1..6]);
	} elsif ($_[2] eq '*' || $_[2] eq $main::mycall) {

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
					$dxchan = $ref->bestdxchan;
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
			
	# do I want users from this channel?
	unless ($self->user->wantpc16) {
		dbg("PCPROT: don't send users to $self->{call}") if isdbg('chanerr');
		return;
	}

	# is it me?
	if ($ncall eq $main::mycall) {
		dbg("PCPROT: trying to alter config on this node from outside!") if isdbg('chanerr');
		return;
	}

	# do we believe this call? 
	unless ($ncall eq $self->{call} || $self->is_believed($ncall)) {
		if (my $ivp = Investigate::get($ncall, $self->{call})) {
			$ivp->store_pcxx($pcno,$line,$origin,@_);
		}
		dbg("PCPROT: We don't believe $ncall on $self->{call}");
		return;
	}

	my $node = Route::Node::get($ncall);
	unless ($node) {
		dbg("PCPROT: Node $ncall not in config") if isdbg('chanerr');
		return;
	}

	# dedupe only that which we potentially process
	if (eph_dup($line)) {
		dbg("PCPROT: dup PC16 detected") if isdbg('chanerr');
		return;
	}

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

		$r = Route::User::get($call) || Route::User->new($call);
		$r->here($here);
		$r->conf($conf);
		$node->lastseen($main::systime);

		push @rout, $r;
				
		# add this station to the user database, if required
		$call =~ s/-\d+$//o;	# remove ssid for users
		my $user = DXUser->get_current($call);
		$user = DXUser->new($call) if !$user;
		$user->homenode($node->call) if !$user->homenode;
		$user->node($node->call);
		$user->lastin($main::systime) unless DXChannel->get($call);
		$user->put;
	}
	$self->process_pc59($pcno, 'A', hexstamp(), Route::Node::get($self->{call}), 
						$node, undef, @rout);
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

	# do we believe this call? 
	unless ($ncall eq $self->{call} || $self->is_believed($ncall)) {
		if (my $ivp = Investigate::get($ncall, $self->{call})) {
			$ivp->store_pcxx($pcno,$line,$origin,@_);
		}
		dbg("PCPROT: We don't believe $ncall on $self->{call}");
		return;
	}

	my $uref = Route::User::get($ucall);
	unless ($uref) {
		dbg("PCPROT: Route::User $ucall not in config") if isdbg('chanerr');
	}
	my $node = Route::Node::get($ncall);
	unless ($node) {
		dbg("PCPROT: Route::Node $ncall not in config") if isdbg('chanerr');
	}			

	return unless $node && $uref;
	
	my @rout;
	if ($self->in_filter_route($node)) {
		if (eph_dup($line)) {
			dbg("PCPROT: dup PC17 detected") if isdbg('chanerr');
			return;
		}
	} else {
		return;
	}

	$self->process_pc59($pcno, 'D', hexstamp(), Route::Node::get($self->{call}), $node, undef, $uref);  
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
		$self->version(53 + $1);
		$self->user->version(53 + $1);
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
	$self->newroute( $_[1] =~ /\!NRt/ );

	# first clear out any nodes on this dxchannel
	my $node = Route::Node::get($self->{call}) ;
	my @rout;
	foreach my $n ($node->nodes) {
		next if $n eq $main::mycall;
		next if $n eq $self->{call};
		my $nref = Route::Node::get($n);
		push @rout, $nref if $nref;
	} 
	$self->process_pc59(21, 'D', hexstamp(), $main::routeroot, $node, undef, @rout) if @rout;
	
	# send the new config
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

	my $parent = Route::Node::get($self->{call});
	unless ($parent) {
		dbg("DXPROT: my parent $self->{call} has disappeared");
		$self->disconnect;
		return;
	}

	if (eph_dup($line)) {
		dbg("PCPROT: dup PC19 detected") if isdbg('chanerr');
		return;
	}

	# parse the PC19
	my @rout;
	for ($i = 1; $i < $#_-1; $i += 4) {
		my $here = $_[$i];
		my $call = uc $_[$i+1];
		my $conf = $_[$i+2];
		my $ver = $_[$i+3];
		next unless defined $here && defined $conf && is_callsign($call);

		# check for sane parameters
		#				$ver = 5000 if $ver eq '0000';
		next if $ver < 5000;	# only works with version 5 software
		next if length $call < 3; # min 3 letter callsigns
		next if $call eq $main::mycall;

		# add this station to the user database, if required (don't remove SSID from nodes)
		my $user = DXUser->get_current($call);
		if (!$user) {
			$user = DXUser->new($call);
			$user->sort('A');
			$user->priv(1);		# I have relented and defaulted nodes
			$user->lockout(1);
			$user->homenode($call);
			$user->node($call);
		}
		$user->wantroutepc19(1) unless defined $user->wantroutepc19;
		$user->lastin($main::systime) unless DXChannel->get($call);
		$user->put;

		# do we believe this call? 
		unless ($call eq $self->{call} || $self->is_believed($call)) {
			my $pt = $user->lastping || 0;
			if ($pt+$investigation_int < $main::systime && !Investigate::get($call, $self->{call})) {
				my $ivp  = Investigate->new($call, $self->{call});
				$ivp->version($ver);
				$ivp->here($here);
				$ivp->store_pcxx($pcno,$line,$origin,'PC19',$here,$call,$conf,$ver,$_[-1]);
			}
			dbg("PCPROT: We don't believe $call on $self->{call}");
			next;
		}

		eph_del_regex("^PC(?:21\\^$call|17\\^[^\\^]+\\^$call)");
				
		my $r = Route::Node::get($call) || Route::Node->new($call);
		$r->here($here);
		$r->conf($conf);
		$r->version($ver);
		$r->lastseen($main::systime);

		if ($self->in_filter_route($r)) {
			push @rout, $r;
		}

		# unbusy and stop and outgoing mail (ie if somehow we receive another PC19 without a disconnect)
		my $mref = DXMsg::get_busy($call);
		$mref->stop_msg($call) if $mref;
	}

	# unshift in the route::node for this interface if isn't present
	if (@rout) {
		unshift @rout, $parent unless $rout[0]->call ne $self->{call};
		$self->process_pc59($pcno, 'A', hexstamp(), Route::Node::get($self->{call}), $parent, undef, @rout);
	}
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
}
		
# delete a cluster from the list
sub handle_21
{
	my $self = shift;
	my $pcno = shift;
	my $line = shift;
	my $origin = shift;
	my $call = uc $_[1];

	return if $call eq $main::mycall;  # don't allow malicious buggers to disconnect me (or ignore loops)!

	unless ($call eq $self->{call} || $self->is_believed($call)) {
		if (my $ivp = Investigate::get($call, $self->{call})) {
			$ivp->store_pcxx($pcno,$line,$origin,@_);
		}
		dbg("PCPROT: We don't believe $call on $self->{call}");
		return;
	}

	eph_del_regex("^PC1[679].*$call");
			
	# if I get a PC21 from the same callsign as self then treat it
	# as a PC39: I have gone away
	if ($call eq $self->call) {
		$self->disconnect(1);
		return;
	}

	my @rout;
	my @new;
	my $parent = Route::Node::get($self->{call});
	unless ($parent) {
		dbg("DXPROT: my parent $self->{call} has disappeared");
		$self->disconnect;
		return;
	}
	$parent->lastseen;

	my $node = Route::Node::get($call);
	if ($node) {
		return if eph_dup($line);
		
		$node->lastseen($main::systime);
		
		# input filter it
		return unless $self->in_filter_route($node);
		push @rout, $node;
	}

	$self->process_pc59($pcno, 'D', hexstamp(), Route::Node::get($self->{call}), $parent, undef, @rout);
}
		

sub handle_22
{
	my $self = shift;
	my $pcno = shift;
	my $line = shift;
	my $origin = shift;
	$self->state('normal');
	$self->{lastping} = 0;
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
	if ($_[1] eq $self->{call}) {
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
	my $node = Route::Node::get($call);
	if ($node) {
		return unless $node->call eq $self->{call};
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
	my $to = $_[1];
	my $from = $_[2];
	my $flag = $_[3];

			
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
							my $nopings = $tochan->user->nopings || $obscount;
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
							my $rref = Route::Node::get($tochan->{call});
							$rref->pingtime($tochan->{pingave}) if $rref;
							$tochan->{nopings} = $nopings; # pump up the timer
							if (my $ivp = Investigate::get($from, $self->{call})) {
								$ivp->handle_ping;
							}
						} elsif (my $rref = Route::Node::get($r->{call})) {
							if (defined $rref->pingtime) {
								$rref->pingtime($rref->pingtime + (($t - $rref->pingtime) / 6));
							} else {
								$rref->pingtime($t);
							}
							if (my $ivp = Investigate::get($from, $self->{call})) {
								$ivp->handle_ping;
							}
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
}


# New style routing handler
sub handle_59
{
	my $self = shift;
	my $pcno = shift;
	my $line = shift;
	my $origin = shift;

	my ($sort, $hexstamp, $ncall) = @_[1,2,3];
	if ($ncall eq $main::mycall) {
		dbg("PCPROT: ignoring PC59 for me") if isdbg('chan');
		return;
	}

	# do this once for filtering with a throwaway routing entry if a new node
	my $fnode = Route::Node::get($ncall) || Route::new($ncall);
	return unless $self->in_filter_route($fnode);

	return if eph_dup($line);

	# mark myself as NewRoute if I get a PC59
	$self->{newroute} = 1 if $ncall eq $self->{call};

	# now do it properly for actions
	my $node = Route::Node::get($ncall) || Route::Node->new($ncall);
	$node->newroute(1);

	# create the user, if required
	my $user = DXUser->get_current($ncall);
	unless ($user) {
		$user = DXUser->new($ncall);
		$user->sort('A');
		$user->priv(1);		# I have relented and defaulted nodes
		$user->lockout(1);
		$user->homenode($ncall);
		$user->node($ncall);
		$user->put;
	}

	# find each of the entries (or create new ones)
	my @refs;
	for my $ent (@_[4..$#_]) {
		next if $ent =~ /^H\d+$/;

		my $ref = $node->dec_pc59($ent);
		if ($ref) {
			my $user = DXUser->get_current($ref->{call});
			unless ($user) {
				$user = DXUser->new($ref->{call});
				$user->homenode($ncall);
				$user->node($ncall);
				if ($ref->isa('Route::Node')) {
					$user->priv(1);		# I have relented and defaulted nodes
					$user->lockout(1);
					$user->sort('A');
				} else {
					$user->sort('U');
				}
				$user->put;
			}
		} else {
			dbg("DXPROT: unknown entity type '$ent'") if isdbg('chan');
			next;
		}
		push @refs, $ref;
	}

	$self->process_pc59($pcno, $sort, $hexstamp, Route::Node::get($self->{call}), $node, $line, @refs);
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

1;
