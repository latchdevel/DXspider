#
# Talk/Announce/Chat Thingy handling
#
# $Id$
#
# Copyright (c) 2005 Dirk Koopman G1TLH
#

use strict;

package Thingy::T;

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
	 	$thing->{Aranea} = Aranea::genmsg($thing, [qw(d)]);
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

sub gen_DXCommandmode
{
	my $thing = shift;
	my $dxchan = shift;
	my $buf;

	return $buf;
}

sub from_DXProt
{
	my $thing = shift;
	while (@_) {
		my $k = shift;
		$thing->{$k} = shift;
	}
	return $thing;
}

sub handle
{
	my $thing = shift;
	my $dxchan = shift;

	$thing->broadcast($dxchan);
}

1;
