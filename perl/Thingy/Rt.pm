#
# Route Thingy handling
#
# Note that this is a generator of pc(16|17|19|21)n and pc(16|17)u
# and a consumer of the fpc versions of the above
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
	my $dxchan = shift;
	
	unless ($thing->{Aranea}) {
		my $ref;
		if ($ref = $thing->{anodes}) {
			$thing->{a} = join(':', map {"$_->{flags}$_->{call}"} @$ref) || '';
		}
		if ($ref = $thing->{anodes}) {
			$thing->{n} = join(':', map {"$_->{flags}$_->{call}"} @$ref) || '';
		}
		if ($ref = $thing->{ausers}) {
			$thing->{u} = join(':', map {"$_->{flags}$_->{call}"} @$ref) || '';
		}
	 	$thing->{Aranea} = Aranea::genmsg($thing, [qw(s a n u)]);
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

# this handles the standard local configuration, it 
# will reset all the config, make / break links and
# will generate pc sentences as required for nodes and users
sub handle_cf
{
	my $thing = shift;
	my $dxchan = shift;
	my $origin = $thing->{user} || $thing->{origin};
	my $chan_call = $dxchan->{call};
	
	my $parent = Route::Node::get($origin);
	unless ($parent) {
		dbg("Thingy::Rt::cf: received from $thing->{origin}/$origin on $chan_call unknown") if isdbg('chanerr');
		return;
	}

	# do nodes
	my ($del, $add);
	my %in;
	if ($thing->{n}) {
		%in = (map {my ($here, $call) = unpack("A1 A*", $_); ($call, $here)} split /:/, $thing->{n});
		my ($tdel, $tadd) = $parent->diff_nodes(keys %in);
		$add = $tadd;
		$del = $tdel;
	}
	if ($thing->{a}) {
		%in = (map {my ($here, $call) = unpack("A1 A*", $_); ($call, $here)} split /:/, $thing->{a});
		my ($tdel, $tadd) = $parent->diff_nodes(keys %in);
		push @$add, @$tadd;
		push @$del, @$tdel;
	}
	if ($add) {
		my @pc21;
		foreach my $call (@$del) {
			RouteDB::delete($call, $chan_call);
			my $ref = Route::Node::get($call);
			push @pc21, $ref->del($parent) if $ref;
		}
		$thing->{pc21n} = \@pc21 if @pc21;
	}
	if ($del) {
		my @pc19;
		foreach my $call (@$add) {
			RouteDB::update($call, $chan_call);
			my $ref = Route::Node::get($call);
			push @pc19, $parent->add($call, 0, $in{$call}) unless $ref;
		}
		$thing->{pc19n} = \@pc19 if @pc19;
	}
	
	# now users
	if ($thing->{u}) {
		%in = (map {my ($here, $call) = unpack "A1 A*", $_; ($call, $here)} split /:/, $thing->{u});
		($del, $add) = $parent->diff_users(keys %in);

		my $call;

		my @pc17;
		foreach $call (@$del) {
			RouteDB::delete($call, $chan_call);
			my $ref = Route::User::get($call);
			if ($ref) {
				$parent->del_user($ref);
				push @pc17, $ref;
			} else {
				dbg("Thingy::Rt::lcf: del user $call not known, ignored") if isdbg('chanerr');
				next;
			}
		}
		if (@pc17) {
			$thing->{pc17n} = $parent;
			$thing->{pc17u} = \@pc17;
		}
	
		my @pc16;
		foreach $call (@$add) {
			RouteDB::update($call, $chan_call);
			push @pc16, _add_user($parent, $call, $in{$call});
		}
		if (@pc16) {
			$thing->{pc16n} = $parent;
			$thing->{pc16u} = \@pc16;
		}
	}

	return $thing;
}


sub _add_user
{
	my $node = shift;
	my $user = shift;
	my $flag = shift;
	
	my @out = $node->add_user($user, $flag);
	my $ur = _upd_user_rec($user, $node);
	$ur->put;
	return @out;
}

sub _upd_user_rec
{
	my $call = shift;
	my $parentcall = shift;
	
	# add this station to the user database, if required
	my $user = DXUser->get_current($call);
	$user = DXUser->new($call) if !$user;
	$user->homenode($parentcall) if !$user->homenode;
	$user->node($parentcall);
	$user->lastin($main::systime) unless DXChannel::get($call);
	return $user;
}

#
# Generate a configuration for onward broadcast
# 
# Basically, this creates a thingy with list of nodes and users that
# are on this node. This the normal method of spreading this
# info whenever a node connects and also periodically.
#

sub new_cf
{
	my $pkg = shift;
	my $thing = $pkg->SUPER::new(@_);
	
	$thing->{'s'} = 'cf';

	my @anodes;
	my @pnodes;
	my @users;
	
	foreach my $dxchan (DXChannel::get_all()) {
		next if $dxchan == $main::me;
		if ($dxchan->is_node) {
			my $ref = Route::Node::get($dxchan->{call});
			push @pnodes, $ref if $ref;
		} elsif ($dxchan->is_aranea) {
			my $ref = Route::Node::get($dxchan->{call});
			push @anodes, $ref if $ref;
		} else {
			my $ref = Route::User::get($dxchan->{call});
			push @users, $ref if $ref;
		}
	}
	$thing->{anodes} = \@anodes if @anodes;
	$thing->{pnodes} = \@pnodes if @pnodes;
	$thing->{ausers} = \@users if @users;
	return $thing;
}

# 
# copy out the PC16 data for a node into the
# pc16n and u slots if there are any users 
#
sub copy_pc16_data
{
	my $thing = shift;
	my $uref = shift;

	$thing->{'s'} = 'cf';

	my @u = map {Route::User::get($_)} $uref->users;
	$thing->{ausers} = \@u;
	return @u;
}



1;
