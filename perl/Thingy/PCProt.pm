#
# This module is the PC Protocol Thingy Handler 
# It will route transforming them on the way as required.
#
# Copyright (c) 2001 Dirk Koopman G1TLH
#
# $Id$
# 

use strict;

use DXDebug;

use vars qw($VERSION $BRANCH);
$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /\d+\.\d+\.(\d+)\.(\d+)/  || (0,0));
$main::build += $VERSION;
$main::branch += $BRANCH;


package Thingy::PC10;
use vars qw(@ISA);
@ISA = qw(Thingy);
	
# incoming talk commands
sub handle
{
	my $self = shift;
	my $dxchan = shift;

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
		$ref->dxchan->talk($from, $to, $vref ? $via : undef, $_[3], $_[6]);
		return;
	}

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
package Thingy::PC11;
use vars qw(@ISA);
@ISA = qw(Thingy);

sub handle
{
	my $self = shift;
	my $dxchan = shift;

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
package Thingy::PC12;
use vars qw(@ISA);
@ISA = qw(Thingy);

sub handle
{
	my $self = shift;
	my $dxchan = shift;

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

	if ($_[2] eq '*' || $_[2] eq $main::mycall) {


		# here's a bit of fun, convert incoming ann with a callsign in the first word
		# or one saying 'to <call>' to a talk if we can route to the recipient
		if ($ann_to_talk) {
			my $call = AnnTalk::is_talk_candidate($_[1], $_[3]);
			if ($call) {
				my $ref = Route::get($call);
				if ($ref) {
					my $dxchan = $ref->dxchan;
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
package Thingy::PC16;
use vars qw(@ISA);
@ISA = qw(Thingy);

sub handle
{
	my $self = shift;
	my $dxchan = shift;


	if (eph_dup($line)) {
		dbg("PCPROT: dup PC16 detected") if isdbg('chanerr');
		return;
	}

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
	my $parent = Route::Node::get($ncall); 

	# if there is a parent, proceed, otherwise if there is a latent PC19 in the PC19list, 
	# fix it up in the routing tables and issue it forth before the PC16
	unless ($parent) {
		my $nl = $pc19list{$ncall};

		if ($nl && @_ > 3) { # 3 because of the hop count!

			# this is a new (remembered) node, now attach it to me if it isn't in filtered
			# and we haven't disallowed it
			my $user = DXUser->get_current($ncall);
			if (!$user) {
				$user = DXUser->new($ncall);
				$user->sort('A');
				$user->priv(1);	# I have relented and defaulted nodes
				$user->lockout(1);
				$user->homenode($ncall);
				$user->node($ncall);
			}

			my $wantpc19 = $user->wantroutepc19;
			if ($wantpc19 || !defined $wantpc19) {
				my $new = Route->new($ncall); # throw away
				if ($self->in_filter_route($new)) {
					my @nrout;
					for (@$nl) {
						$parent = Route::Node::get($_->[0]);
						$dxchan = $parent->dxchan if $parent;
						if ($dxchan && $dxchan ne $self) {
							dbg("PCPROT: PC19 from $self->{call} trying to alter locally connected $ncall, ignored!") if isdbg('chanerr');
							$parent = undef;
						}
						if ($parent) {
							my $r = $parent->add($ncall, $_->[1], $_->[2]);
							push @nrout, $r unless @nrout;
						}
					}
					$user->wantroutepc19(1) unless defined $wantpc19; # for now we work on the basis that pc16 = real route 
					$user->lastin($main::systime) unless DXChannel->get($ncall);
					$user->put;
						
					# route the pc19 - this will cause 'stuttering PC19s' for a while
					$self->route_pc19(@nrout) if @nrout ;
					$parent = Route::Node::get($ncall);
					unless ($parent) {
						dbg("PCPROT: lost $ncall after sending PC19 for it?");
						return;
					}
				} else {
					return;
				}
				delete $pc19list{$ncall};
			}
		} else {
			dbg("PCPROT: Node $ncall not in config") if isdbg('chanerr');
			return;
		}
	} else {
				
		$dxchan = $parent->dxchan;
		if ($dxchan && $dxchan ne $self) {
			dbg("PCPROT: PC16 from $self->{call} trying to alter locally connected $ncall, ignored!") if isdbg('chanerr');
			return;
		}

		# input filter if required
		return unless $self->in_filter_route($parent);
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
				
		$r = Route::User::get($call);
		my $flags = Route::here($here)|Route::conf($conf);
				
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
		$user->lastin($main::systime) unless DXChannel->get($call);
		$user->put;
	}
			
	$self->route_pc16($parent, @rout) if @rout;
}
		
# remove a user
package Thingy::PC17;
use vars qw(@ISA);
@ISA = qw(Thingy);

sub handle
{
	my $self = shift;
	my $dxchan = shift;
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
}
		
# link request
package Thingy::PC18;
use vars qw(@ISA);
@ISA = qw(Thingy);

sub handle
{
	my $self = shift;
	my $dxchan = shift;
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

	# first clear out any nodes on this dxchannel
	my $parent = Route::Node::get($self->{call});
	my @rout = $parent->del_nodes;
	$self->route_pc21(@rout, $parent) if @rout;
	$self->send_local_config();
	$self->send(pc20());
}
		
# incoming cluster list
package Thingy::PC19;
use vars qw(@ISA);
@ISA = qw(Thingy);

sub handle
{
	my $self = shift;
	my $dxchan = shift;

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
	for ($i = 1; $i < $#_-1; $i += 4) {
		my $here = $_[$i];
		my $call = uc $_[$i+1];
		my $conf = $_[$i+2];
		my $ver = $_[$i+3];
		next unless defined $here && defined $conf && is_callsign($call);

		eph_del_regex("^PC(?:21\\^$call|17\\^[^\\^]+\\^$call)");
				
		# check for sane parameters
		#				$ver = 5000 if $ver eq '0000';
		next if $ver < 5000;	# only works with version 5 software
		next if length $call < 3; # min 3 letter callsigns
		next if $call eq $main::mycall;

		# check that this PC19 isn't trying to alter the wrong dxchan
		my $dxchan = DXChannel->get($call);
		if ($dxchan && $dxchan != $self) {
			dbg("PCPROT: PC19 from $self->{call} trying to alter wrong locally connected $call, ignored!") if isdbg('chanerr');
			next;
		}

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

		my $r = Route::Node::get($call);
		my $flags = Route::here($here)|Route::conf($conf);

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
			}
			if ($r->version ne $ver || $r->flags != $flags) {
				$r->version($ver);
				$r->flags($flags);
				push @rout, $r unless $ar;
			}
		} else {

			# if he is directly connected or allowed then add him, otherwise store him up for later
			if ($call eq $self->{call} || $user->wantroutepc19) {
				my $new = Route->new($call); # throw away
				if ($self->in_filter_route($new)) {
					my $ar = $parent->add($call, $ver, $flags);
					$user->wantroutepc19(1) unless defined $user->wantroutepc19;
					push @rout, $ar if $ar;
				} else {
					next;
				}
			} else {
				$pc19list{$call} = [] unless exists $pc19list{$call};
				my $nl = $pc19list{$call};
				push @{$pc19list{$call}}, [$self->{call}, $ver, $flags] unless grep $_->[0] eq $self->{call}, @$nl;
			}
		}

		# unbusy and stop and outgoing mail (ie if somehow we receive another PC19 without a disconnect)
		my $mref = DXMsg::get_busy($call);
		$mref->stop_msg($call) if $mref;
				
		$user->lastin($main::systime) unless DXChannel->get($call);
		$user->put;
	}


	$self->route_pc19(@rout) if @rout;
}
		
# send local configuration
package Thingy::PC20;
use vars qw(@ISA);
@ISA = qw(Thingy);

sub handle
{
	my $self = shift;
	my $dxchan = shift;
	$self->send_local_config();
	$self->send(pc22());
	$self->state('normal');
	$self->{lastping} = 0;
}
		
# delete a cluster from the list
package Thingy::PC21;
use vars qw(@ISA);
@ISA = qw(Thingy);

sub handle
{
	my $self = shift;
	my $dxchan = shift;
	my $call = uc $_[1];

	eph_del_regex("^PC1[679].*$call");
			
	# if I get a PC21 from the same callsign as self then treat it
	# as a PC39: I have gone away
	if ($call eq $self->call) {
		$self->disconnect(1);
		return;
	}

	# check to see if we are in the pc19list, if we are then don't bother with any of
	# this routing table manipulation, just remove it from the list and dump it
	my @rout;
	if (my $nl = $pc19list{$call}) {
		$pc19list{$call} = [ grep {$_->[0] ne $self->{call}} @$nl ];
		delete $pc19list{$call} unless @{$pc19list{$call}};
	} else {
				
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
	}

	$self->route_pc21(@rout) if @rout;
}
		

package Thingy::PC22;
use vars qw(@ISA);
@ISA = qw(Thingy);

sub handle
{
	my $self = shift;
	my $dxchan = shift;
	$self->state('normal');
	$self->{lastping} = 0;
}
				
# WWV info
package Thingy::PC23;
use vars qw(@ISA);
@ISA = qw(Thingy);

sub handle
{
	my $self = shift;
	my $dxchan = shift;
			
	# route 'foreign' pc27s 
	if ($pcno == 27) {
		if ($_[8] ne $main::mycall) {
			$self->route($_[8], $line);
			return;
		}
	}

	return if $rspfcheck and !$self->rspfcheck(1, $_[8], $_[7]);

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
package Thingy::PC24;
use vars qw(@ISA);
@ISA = qw(Thingy);

sub handle
{
	my $self = shift;
	my $dxchan = shift;
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

	$self->route_pc24($ref, $_[3]);
}
		
# merge request
package Thingy::PC25;
use vars qw(@ISA);
@ISA = qw(Thingy);

sub handle
{
	my $self = shift;
	my $dxchan = shift;
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
			$self->send_frame($main::me, pc26(@{$in}[0..4], $_[2]));
		}
	}

	# wwv
	if ($_[4] > 0) {
		my @in = reverse Geomag::search(0, $_[4], time, 1);
		my $in;
		foreach $in (@in) {
			$self->send_frame($main::me, pc27(@{$in}[0..5], $_[2]));
		}
	}
}

sub handle_26 {goto &handle_11}
sub handle_27 {goto &handle_23}

# mail/file handling
package Thingy::PC28;
use vars qw(@ISA);
@ISA = qw(Thingy);

sub handle
{
	my $self = shift;
	my $dxchan = shift;
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
		
package Thingy::PC34;
use vars qw(@ISA);
@ISA = qw(Thingy);

sub handle
{
	my $self = shift;
	my $dxchan = shift;
	if (eph_dup($line, $eph_pc34_restime)) {
		dbg("PCPROT: dupe PC34, ignored") if isdbg('chanerr');
	} else {
		$self->process_rcmd($_[1], $_[2], $_[2], $_[3]);
	}
}
		
# remote command replies
package Thingy::PC35;
use vars qw(@ISA);
@ISA = qw(Thingy);

sub handle
{
	my $self = shift;
	my $dxchan = shift;
	eph_del_regex("^PC35\\^$_[2]\\^$_[1]\\^");
	$self->process_rcmd_reply($_[1], $_[2], $_[1], $_[3]);
}
		
sub handle_36 {goto &handle_34}

# database stuff
package Thingy::PC37;
use vars qw(@ISA);
@ISA = qw(Thingy);

sub handle
{
	my $self = shift;
	my $dxchan = shift;
	DXDb::process($self, $line);
}

# node connected list from neighbour
package Thingy::PC38;
use vars qw(@ISA);
@ISA = qw(Thingy);

sub handle
{
	my $self = shift;
	my $dxchan = shift;
}
		
# incoming disconnect
package Thingy::PC39;
use vars qw(@ISA);
@ISA = qw(Thingy);

sub handle
{
	my $self = shift;
	my $dxchan = shift;
	if ($_[1] eq $self->{call}) {
		$self->disconnect(1);
	} else {
		dbg("PCPROT: came in on wrong channel") if isdbg('chanerr');
	}
}

sub handle_40 {goto &handle_28}
		
# user info
package Thingy::PC41;
use vars qw(@ISA);
@ISA = qw(Thingy);

sub handle
{
	my $self = shift;
	my $dxchan = shift;
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
package Thingy::PC49;
use vars qw(@ISA);
@ISA = qw(Thingy);

sub handle
{
	my $self = shift;
	my $dxchan = shift;

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
package Thingy::PC50;
use vars qw(@ISA);
@ISA = qw(Thingy);

sub handle
{
	my $self = shift;
	my $dxchan = shift;

	my $call = $_[1];
	my $node = Route::Node::get($call);
	if ($node) {
		return unless $node->call eq $self->{call};
		$node->usercount($_[2]);

		# input filter if required
		return unless $self->in_filter_route($node);

		$self->route_pc50($node, $_[2], $_[3]) unless eph_dup($line);
	}
}
		
# incoming ping requests/answers
package Thingy::PC51;
use vars qw(@ISA);
@ISA = qw(Thingy);

sub handle
{
	my $self = shift;
	my $dxchan = shift;
	my $to = $_[1];
	my $from = $_[2];
	my $flag = $_[3];

			
	# is it for us?
	if ($to eq $main::mycall) {
		if ($flag == 1) {
			$self->send_frame($main::me, pc51($from, $to, '0'));
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
}

# dunno but route it
package Thingy::PC75;
use vars qw(@ISA);
@ISA = qw(Thingy);

sub handle
{
	my $self = shift;
	my $dxchan = shift;
	my $call = $_[1];
	if ($call ne $main::mycall) {
		$self->route($call, $line);
	}
}

# WCY broadcasts
package Thingy::PC73;
use vars qw(@ISA);
@ISA = qw(Thingy);

sub handle
{
	my $self = shift;
	my $dxchan = shift;
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
package Thingy::PC84;
use vars qw(@ISA);
@ISA = qw(Thingy);

sub handle
{
	my $self = shift;
	my $dxchan = shift;
	$self->process_rcmd($_[1], $_[2], $_[3], $_[4]);
}

# remote command replies
package Thingy::PC85;
use vars qw(@ISA);
@ISA = qw(Thingy);

sub handle
{
	my $self = shift;
	my $dxchan = shift;
	$self->process_rcmd_reply($_[1], $_[2], $_[3], $_[4]);
}
	 
# if get here then rebroadcast the thing with its Hop count decremented (if
# there is one). If it has a hop count and it decrements to zero then don't
# rebroadcast it.
#
# NOTE - don't arrive here UNLESS YOU WANT this lump of protocol to be
#        REBROADCAST!!!!
#

package Thingy::PCdefault;
use vars qw(@ISA);
@ISA = qw(Thingy);

sub handle
{
	my $self = shift;
	my $dxchan = shift;

	if (eph_dup($line)) {
		dbg("PCPROT: Ephemeral dup, dropped") if isdbg('chanerr');
	} else {
		unless ($self->{isolate}) {
			DXChannel::broadcast_nodes($line, $self); # send it to everyone but me
		}
	}
}

1;
