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
$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /\d+\.\d+\.(\d+)\.(\d+)/  || (0,0));
$main::build += $VERSION;
$main::branch += $BRANCH;

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
	 	$thing->{Aranea} = Aranea::genmsg($thing, 'Rloc', @items);
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
	($thing->{hops}) = $thing->{DXProt} =~ /\^H(\d+)\^?~?$/ if exists $thing->{DXProt};
	return $thing;
}

sub handle
{
	my $thing = shift;
	my $dxchan = shift;

	$thing->broadcast($dxchan);
}

sub in_filter
{
	my $thing = shift;
	my $dxchan = shift;
	
	# global route filtering on INPUT
	if ($dxchan->{inroutefilter}) {
		my ($filter, $hops) = $dxchan->{inroutefilter}->it($thing->{routedata});
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
	
	# global route filtering on INPUT
	if ($dxchan->{routefilter}) {
		my ($filter, $hops) = $dxchan->{routefilter}->it($thing->{routedata});
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
1;
