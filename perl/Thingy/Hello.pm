#
# Hello Thingy handling
#
# $Id$
#
# Copyright (c) 2005 Dirk Koopman G1TLH
#

use strict;

package Thingy::Hello;

use vars qw($VERSION $BRANCH);
$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /^\d+\.\d+(?:\.(\d+)\.(\d+))?$/  || (0,0));
$main::build += $VERSION;
$main::branch += $BRANCH;

use DXChannel;
use DXDebug;
use Verify;
use Thingy;

use vars qw(@ISA $verify_on_login);
@ISA = qw(Thingy);

$verify_on_login = 1;			# make sure that a HELLO coming from
                                # the dxchan call is authentic

sub gen_Aranea
{
	my $thing = shift;
	unless ($thing->{Aranea}) {
		my $s = sprintf "%X", int(rand() * 100000000);
		my $auth = Verify->new("DXSp,$main::mycall,$s,$main::version,$main::build");
		$thing->{Aranea} = Aranea::genmsg($thing, 'HELLO', sw=>'DXSp',
										  v=>$main::version,
										  b=>$main::build,
										  's'=>$s,
										  auth=>$auth->challenge($main::me->user->passphrase)
									  );
	}
	return $thing->{Aranea};
}

sub handle
{
	my $thing = shift;
	my $dxchan = shift;
	
	# verify authenticity
	if ($dxchan->{call} eq $thing->{origin}) {

		# for directly connected calls
		if ($verify_on_login) {
			my $pp = $dxchan->user->passphrase;
			unless ($pp) {
				dbglog('err', "Thingy::Hello::handle: verify on and $thing->{origin} has no passphrase");
				$dxchan->disconnect;
				return;
			}
			my $auth = Verify->new("DXSp,$thing->{origin},$thing->{s},$thing->{v},$thing->{b}");
			unless ($auth->verify($thing->{auth}, $dxchan->user->passphrase)) {
				dbglog('err', "Thingy::Hello::handle: verify on and $thing->{origin} failed auth check");
				$dxchan->disconnect;
				return;
			}
		}
		if ($dxchan->{state} ne 'normal') {
			$dxchan->start($dxchan->{conn}->{csort}, $dxchan->{conn}->{outbound} ? 'O' : 'A');
			if ($dxchan->{outbound}) {
				my $thing = Thingy::Hello->new();
				$thing->send($dxchan);
			}
		}
	} else {
		
		# for otherwise connected calls, that come in relayed from other nodes
		# note that we cannot do any connections at this point
		my $nref = Route::Node::get($thing->{origin});
		unless ($nref) {
			my $v = $thing->{user} ? undef : $thing->{v};
			$nref = Route::Node->new($thing->{origin}, $v, 1);
		}
		if (my $user = $thing->{user}) {
			my $ur = Route::get($user);
			unless ($ur) {
				my $uref = DXUser->get_current($user);
				if ($uref->is_node || $uref->is_aranea) {
					$nref->add($user, $thing->{v}, 1);
				} else {
					$nref->add_user($user, 1);
				}
			}
		}
	}
	RouteDB::update($thing->{origin}, $dxchan->{call}, $thing->{hopsaway});
	RouteDB::update($thing->{user}, $dxchan->{call}, $thing->{hopsaway}) if $thing->{user};
		
	$thing->broadcast($dxchan);
}

sub new
{
	my $pkg = shift;
	my $thing = $pkg->SUPER::new(origin=>$main::mycall);
	return $thing;
}
1;
