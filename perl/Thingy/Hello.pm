#
# Hello Thingy handling
#
# Note that this is a generator of pc19n and pc16n/pc16u
# and a consumer of fpc19n and fpc16n
#
# $Id$
#
# Copyright (c) 2005 Dirk Koopman G1TLH
#

use strict;

package Thingy::Hello;

use vars qw($VERSION $BRANCH);

main::mkver($VERSION = q$Revision$);

use DXChannel;
use DXDebug;
use Verify;
use Thingy;
use Thingy::RouteFilter;
use Thingy::Rt;

use vars qw(@ISA $verify_on_login);
@ISA = qw(Thingy Thingy::RouteFilter);

$verify_on_login = 1;			# make sure that a HELLO coming from
                                # the dxchan call is authentic

sub gen_Aranea
{
	my $thing = shift;
	my $dxchan = shift;
	
	unless ($thing->{Aranea}) {
		if ($thing->{user}) {
			$thing->{h} ||= $dxchan->here;
		} else {
			$thing->add_auth;
			$thing->{sw} ||= 'DXSp';
			$thing->{v} ||= $main::version;
			$thing->{b} ||= $main::build;
			$thing->{h} ||= $main::me->here;
		}
		
		$thing->{Aranea} = Aranea::genmsg($thing, [qw(sw h v b s auth)]);
	}
	return $thing->{Aranea};
}

sub handle
{
	my $thing = shift;
	my $dxchan = shift;
	
	my $origin = $thing->{origin};
	my $node = $dxchan->{call};
	
	my $nref;

	$thing->{pc19n} ||= [];
	
	# verify authenticity
	if ($node eq $origin) {

		# for directly connected calls
		if ($verify_on_login && !$thing->{user}) {
			my $pp = $dxchan->user->passphrase;
			unless ($pp) {
				dbglog('err', "Thingy::Hello::handle: verify on and $origin has no passphrase");
				$dxchan->disconnect;
				return;
			}
			my $auth = Verify->new("DXSp,$origin,$thing->{s},$thing->{v},$thing->{b}");
			unless ($auth->verify($thing->{auth}, $dxchan->user->passphrase)) {
				dbglog('err', "Thingy::Hello::handle: verify on and $origin failed auth check");
				$dxchan->disconnect;
				return;
			}
		}
		if ($dxchan->{state} ne 'normal') {
			$nref = $main::routeroot->add($origin, $thing->{v}, $thing->{h});
			push @{$thing->{pc19n}}, $nref if $nref;
			$dxchan->start($dxchan->{conn}->{csort}, $dxchan->{conn}->{outbound} ? 'O' : 'A');
			if ($dxchan->{outbound}) {
				my $thing = Thingy::Hello->new();
				$thing->send($dxchan);

				# broadcast our configuration to the world
				$thing = Thingy::Rt->new_lcf;
				$thing->broadcast;
			}
		}
		$nref = Route::Node::get($origin);
		$nref->np(1);
	} else {
		
		# for otherwise connected calls, that come in relayed from other nodes
		# note that we cannot do any connections at this point
		$nref = Route::Node::get($origin);
		unless ($nref) {
			my $v = $thing->{user} ? undef : $thing->{v};
			$nref = Route::Node->new($origin, $v, 1);
			push @{$thing->{pc19n}}, $nref;
			$nref->np(1);
		}
	}

	# handle "User"
	if (my $user = $thing->{user}) {
		my $ur = Route::get($user);
		unless ($ur) {
			my $uref = DXUser->get_current($user) || Thingy::Hello::_upd_user_rec($user, $origin)->put;
			if ($uref->is_node || $uref->is_aranea) {
			    $ur = $nref->add($user, $thing->{v}, $thing->{h});
				push @{$thing->{pc19n}}, $ur if $ur;
			} else {
				$thing->{pc16n} = $nref;
				$thing->{pc16u} = [$ur = $nref->add_user($user, $thing->{h})];
			}
		}
		$ur->np(1);
	} else {
		$nref->version($thing->{v}) unless $nref->version;
		$nref->build($thing->{b}) unless $nref->build;
		$nref->sw($thing->{sw}) unless $nref->sw;
		$nref->here($thing->{h}) if exists $thing->{h};
	}

	RouteDB::update($origin, $node, $thing->{hopsaway});
	RouteDB::update($thing->{user}, $node, $thing->{hopsaway}) if $thing->{user};
	
	delete $thing->{pc19n} unless @{$thing->{pc19n}};
	
	$thing->broadcast($dxchan);
}

1;
