#
# Bye Thingy handling
#
# $Id$
#
# Copyright (c) 2005 Dirk Koopman G1TLH
#

use strict;

package Thingy::Bye;

use vars qw($VERSION $BRANCH);
$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /^\d+\.\d+(?:\.(\d+)\.(\d+))?$/  || (0,0));
$main::build += $VERSION;
$main::branch += $BRANCH;

use DXChannel;
use DXDebug;
use Verify;
use Thingy;

use vars qw(@ISA);
@ISA = qw(Thingy);

sub gen_Aranea
{
	my $thing = shift;
	unless ($thing->{Aranea}) {
		my $s = sprintf "%X", int(rand() * 100000000);
		my $auth = Verify->new("DXSp,$main::mycall,$s");
		$thing->{Aranea} = Aranea::genmsg($thing, 'Bye',
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
#		if ($Thingy::Hello::verify_on_login) {
#			my $pp = $dxchan->user->passphrase;
#			unless ($pp) {
#				dbglog('err', "Thingy::Bye::handle: verify on and $thing->{origin} has no passphrase");
#				return;
#			}
#			my $auth = Verify->new("DXSp,$thing->{origin},$thing->{s}");
#			unless ($auth->verify($thing->{auth}, $dxchan->user->passphrase)) {
#				dbglog('err', "Thingy::Bye::handle: verify on and $thing->{origin} failed auth check");
#				return;
#			}
#		}
		
		my $int = $thing->{user} || $thing->{origin};
		RouteDB::delete_interface($int);
	} else {
		
		# for otherwise connected calls, that come in relayed from other nodes
		# note that we cannot do any connections at this point
		my $nref = Route::Node::get($thing->{origin});
		if ($nref) {
			if (my $user = $thing->{user}) {
				my $ur = Route::get($user);
				if ($ur) {
					if ($ur->isa('Route::Node')) {
						$nref->del($ur);
					} elsif ($ur->isa('Route::User')) {
						$nref->del_user($ur);
					}
				}
			}
		}
	}

		
	$thing->broadcast($dxchan);
}

sub new
{
	my $pkg = shift;
	my $thing = $pkg->SUPER::new(origin=>$main::mycall, @_);
	return $thing;
}
1;
