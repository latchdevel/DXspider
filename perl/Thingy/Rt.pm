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
use Thingy::RouteFilter;
use Spot;

use vars qw(@ISA);
@ISA = qw(Thingy Thingy::RouteFilter);

sub gen_Aranea
{
	my $thing = shift;
	unless ($thing->{Aranea}) {
		my $ref;
		if ($ref = $thing->{anodes}) {
			$thing->{n} = join(':', map {$_->{call}} @$ref);
		}
		if ($ref = $thing->{ausers}) {
			$thing->{u} = join(':', map {$_->{call}} @$ref);
		}
	 	$thing->{Aranea} = Aranea::genmsg($thing, [qw(s n u)]);
	}
 	return $thing->{Aranea};
}

sub from_Aranea
{
	my $thing = shift;
	return unless $thing;
	return $thing;
}

sub handle
{
	my $thing = shift;
	my $dxchan = shift;

	if ($thing->{'s'}) {
		my $sub = "handle_$thing->{s}";
		if ($thing->can($sub)) {
			no strict 'refs';
			$thing = $thing->$sub($dxchan);
		}

		$thing->broadcast($dxchan) if $thing;
	}
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

#
# Generate a configuration for onward broadcast
# 
# Basically, this creates a thingy with list of nodes and users that
# are on this node. This the normal method of spreading this
# info whenever a node connects and also periodically.
#

sub new_lcf
{
	my $pkg = shift;
	my $thing = $pkg->SUPER::new(@_);
	
	$thing->{'s'} = 'lcf';

	my @nodes;
	my @users;
	
	foreach my $dxchan (DXChannel::get_all()) {
		if ($dxchan->is_node || $dxchan->is_aranea) {
			my $ref = Route::Node::get($dxchan->{call});
			push @nodes, $ref if $ref;
		} else {
			my $ref = Route::User::get($dxchan->{call});
			push @users, $ref if $ref;
		}
	}
	$thing->{anodes} = \@nodes if @nodes;
	$thing->{ausers} = \@users if @users;
	return $thing;
}




1;
