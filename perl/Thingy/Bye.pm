#
# Bye Thingy handling
#
# Note that this is a generator of pc21n and pc17n/pc17u
# and a consumer of fpc21n and fpc21n
#
# $Id$
#
# Copyright (c) 2005 Dirk Koopman G1TLH
#

use strict;

package Thingy::Bye;

use vars qw($VERSION $BRANCH);

main::mkver($VERSION = q$Revision$);

use DXChannel;
use DXDebug;
use Verify;
use Thingy;
use Thingy::RouteFilter;

use vars qw(@ISA);
@ISA = qw(Thingy Thingy::RouteFilter);

sub gen_Aranea
{
	my $thing = shift;
	unless ($thing->{Aranea}) {
		$thing->{Aranea} = Aranea::genmsg($thing, [qw(s auth)]);
	}
	return $thing->{Aranea};
}

sub handle
{
	my $thing = shift;
	my $dxchan = shift;

	# fix the interface routing
	my $intcall = $thing->{user} || $thing->{origin};
	if ($dxchan->{call} eq $thing->{origin} && !$thing->{user}) {
		RouteDB::delete_interface($intcall);
	} else {
		RouteDB::delete($intcall, $dxchan->{call});
	}

	# pc prot generation
	my @pc21;
	if (my $user = $thing->{user}) {
		my $parent = Route::Node::get($thing->{origin});
		my $uref = Route::get($user);
		if ($parent && $uref) {
			if ($uref->isa('Route::Node')) {
				@pc21 = $parent->del($uref);
			} else {
				$parent->del_user($uref);
				$thing->{pc17n} = $parent;
				$thing->{pc17u} = [$uref];
			}
		}
	} else {
		my $parent = Route::get($thing->{origin});
		@pc21 = $parent->del_nodes if $parent;
	}

	$thing->{pc21n} = \@pc21 if @pc21;
		
	$thing->broadcast($dxchan);
}

1;
