#
# Route Thingy handling
#
# $Id$
#
# Copyright (c) 2005 Dirk Koopman G1TLH
#

use strict;

package Thingy::Rt;

use vars qw($VERSION $BRANCH);

main::mkver($VERSION = q$Revision$);

use DXChannel;
use DXDebug;
use DXUtil;
use Thingy;
use Spot;

use vars qw(@ISA);
@ISA = qw(Thingy);

sub gen_Aranea
{
	my $thing = shift;
	unless ($thing->{Aranea}) {
		my @items;
		push @items, 's', $thing->{'s'} if $thing->{'s'};
		push @items, 'n', $thing->{n} if $thing->{n};
		push @items, 'v', $thing->{v} if $thing->{v};
		push @items, 'u', $thing->{u} if $thing->{u};
	 	$thing->{Aranea} = Aranea::genmsg($thing, 'RT', @items) if @items;
	}
 	return $thing->{Aranea};
}

sub from_Aranea
{
	my $thing = shift;
	return unless $thing;
	return $thing;
}

sub gen_DXProt
{
	my $thing = shift;
	my $dxchan = shift;
	my $s = $thing->{'s'};
	if ($s eq 'au') {
		my $n = $thing->{n} || $thing->{user};
		my @out;
		if ($n && (my $u = $thing->{u})) {
			my $s = '';
			for (split /:/, $u) {
				my ($here, $call) = unpack "A1 A*", $_;
				my $str = sprintf "^%s * %d", $call, $here;
				if (length($s) + length($str) > $DXProt::sentencelth) {
					push @out, "PC16^$n" . $s . sprintf "^%s^", DXProt::get_hops(16);
					$s = '';
				}
				$s .= $str;
			}
			push @out, "PC16^$n" . $s . sprintf "^%s^", DXProt::get_hops(16);
			$thing->{DXProt} = @out > 1 ? \@out : $out[0];
		}
	} elsif ($s eq 'du') {
		my $n = $thing->{n} || $thing->{user};
		my $hops = DXProt::get_hops(17);
		if ($n && (my $u = $thing->{u})) {
			$thing->{DXProt} = "PC17^$u^$n^$hops^"; 
		}
	} elsif ($s eq 'an') {
	} elsif ($s eq 'dn') {
	}
	return $thing->{DXProt};
}

#sub gen_DXCommandmode
#{
#	my $thing = shift;
#	my $dxchan = shift;
#	my $buf;
#
#	return $buf;
#}

sub from_DXProt
{
	my $thing = shift;
	while (@_) {
		my $k = shift;
		$thing->{$k} = shift;
	}
	($thing->{hops}) = $thing->{DXProt} =~ /\^H(\d+)\^?~?$/ if exists $thing->{DXProt};
	return $thing;
}

sub handle
{
	my $thing = shift;
	my $dxchan = shift;

	if ($thing->{t}) {
		my $sub = "handle_$thing->{t}";
		if ($thing->can($sub)) {
			no strict 'refs';
			$thing = $thing->$sub($dxchan);
		}

		$thing->broadcast($dxchan) if $thing;
	}
}

# these contain users and either a node (for externals) or the from address 
sub handle_au
{
	my $thing = shift;
	my $dxchan = shift;

	my $node = $thing->{n} || $thing->{user};
	my $nref = Route::Node::get($node);

	if ($nref) {
		if (my $u = $thing->{u}) {
			for (split /:/, $u) {
				my ($here, $call) = unpack "A1 A*", $_;
				add_user($nref, $call, $here);
				my $h = $dxchan->{call} eq $nref->{call} ? 3 : ($thing->{hops} || 99);
				RouteDB::update($call, $dxchan->{call}, $h);
			}
		}
	} else {
		dbg("Thingy::Rt::au: $node not found") if isdbg('chanerr');
		return;
	}
	return $thing;
}

sub handle_du
{
	my $thing = shift;
	my $dxchan = shift;

	my $node = $thing->{n} || $thing->{user};
	my $nref = Route::Node::get($node);

	if ($nref) {
		if (my $u = $thing->{u}) {
			for (split /:/, $u) {
				my ($here, $call) = unpack "A1 A*", $_;
				my $uref = Route::User::get($call);
				unless ($uref) {
					dbg("Thingy::Rt::du $call not a user") if isdbg('chanerr');
					next;
				}
				$nref->del_user($uref);
				RouteDB::delete($call, $dxchan->{call});
			}
			RouteDB::update($nref->{call}, $dxchan->{call}, $dxchan->{call} eq $nref->{call} ? 2 : ($thing->{hops} || 99));
		}
	} else {
		dbg("Thingy::Rt::du: $node not found") if isdbg('chanerr');
		return;
	}

	return $thing;
}

sub in_filter
{
	my $thing = shift;
	my $dxchan = shift;
	
	# global route filtering on INPUT
	if ($dxchan->{inroutefilter}) {
		my $r = Route::Node::get($thing->{origin});
		my ($filter, $hops) = $dxchan->{inroutefilter}->it($dxchan->{call}, $dxchan->{dxcc}, $dxchan->{itu}, $dxchan->{cq}, $r->{call}, $r->{dxcc}, $r->{itu}, $r->{cq}, $dxchan->{state}, $r->{state});
		unless ($filter) {
			dbg("PCPROT: Rejected by input route filter") if isdbg('chanerr');
			return;
		}
	}
	return 1;
}

sub out_filter
{
	my $thing = shift;
	my $dxchan = shift;
	
	# global route filtering on OUTPUT
	if ($dxchan->{routefilter}) {
		my $r = Route::Node::get($thing->{origin});
		my ($filter, $hops) = $dxchan->{routefilter}->it($dxchan->{call}, $dxchan->{dxcc}, $dxchan->{itu}, $dxchan->{cq}, $r->{call}, $r->{dxcc}, $r->{itu}, $r->{cq}, $dxchan->{state}, $r->{state});		
		unless ($filter) {
			dbg("PCPROT: Rejected by output route filter") if isdbg('chanerr');
			return;
		}
		$thing->{hops} = $hops if $hops;
	} elsif ($dxchan->{isolate}) {
		return;
	}
	return 1;
}

sub add_user
{
	my $node = shift;
	my $user = shift;
	my $flag = shift;
	
	$node->add_user($user, $flag);
	my $ur = upd_user_rec($user, $node);
	$ur->put;
}

sub upd_user_rec
{
	my $call = shift;
	my $parentcall = shift;
	
	# add this station to the user database, if required
	$call =~ s/-\d+$//o;	# remove ssid for users
	my $user = DXUser->get_current($call);
	$user = DXUser->new($call) if !$user;
	$user->homenode($parentcall) if !$user->homenode;
	$user->node($parentcall);
	$user->lastin($main::systime) unless DXChannel->get($call);
	return $user;
}
1;
