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
	 	$thing->{Aranea} = Aranea::genmsg($thing, 'RT', @items);
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

sub handle_eau
{
	my $thing = shift;
	my $dxchan = shift;

	if (my $d = $thing->{d}) {
		my $nref;
		for (split /:/, $d) {
			my ($type, $here, $call) = unpack "A1 A1 A*", $_;
			if ($type eq 'U') {
				unless ($nref) {
					dbg("Thingy::Rt::ea need a node before $call");
					return;
				}
				add_user($nref, $call, $here);
				my $h = $dxchan->{call} eq $nref->{call} ? 3 : ($thing->{hops} || 99);
				RouteDB::update($call, $dxchan->{call}, $h);
			} elsif ($type eq 'N') {
				$nref = Route::Node::get($call);
				unless ($nref) {
					dbg("Thingy::Rt::ea need a definition for $call");
					return;
				}
				my $h = $dxchan->{call} eq $nref->{call} ? 2 : ($thing->{hops} || 99);
				RouteDB::update($nref->{call}, $dxchan->{call}, $h);
			} else {
				dbg("Thingy::Rt::ea invalid type $type");
				return;
			}
		}
	}
	return $thing;
}

sub handle_edu
{
	my $thing = shift;
	my $dxchan = shift;

	if (my $d = $thing->{d}) {
		my $nref;
		for (split /:/, $d) {
			my ($type, $here, $call) = unpack "A1 A1 A*", $_;
			if ($type eq 'U') {
				unless ($nref) {
					dbg("Thingy::Rt::edu need a node before $call");
					return;
				}
				my $uref = Route::User::get($call);
				unless ($uref) {
					dbg("Thingy::Rt::edu $call not a user") if isdbg('chanerr');
					next;
				}
				$nref->del_user($uref);
				RouteDB::delete($call, $dxchan->{call});
			} elsif ($type eq 'N') {
				$nref = Route::Node::get($call);
				unless ($nref) {
					dbg("Thingy::Rt::ed need a definition for $call");
					return;
				}
				RouteDB::update($nref->{call}, $dxchan->{call}, $dxchan->{call} eq $nref->{call} ? 2 : ($thing->{hops} || 99));
			} else {
				dbg("Thingy::Rt::ed invalid type $type");
				return;
			}
		}
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
