#
# Dx Thingy handling
#
# $Id$
#
# Copyright (c) 2005 Dirk Koopman G1TLH
#

use strict;

package Thingy::Dx;

use vars qw($VERSION $BRANCH);
$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /^\d+\.\d+(?:\.(\d+)\.(\d+))?$/  || (0,0));
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
		my $sd = $thing->{spotdata};
		my @items = (
					 f=>$sd->[0],
					 c=>$sd->[1],
					);
		push @items, ('b', $sd->[4]) unless $thing->{user};
		push @items, ('st', sprintf("%X", $sd->[2] / 60), 'o', $sd->[7]) unless $sd->[7] eq $main::mycall;
		push @items, ('i', $sd->[3]) if $sd->[3];
	 	$thing->{Aranea} = Aranea::genmsg($thing, 'DX', @items);
	}
 	return $thing->{Aranea};
}

sub from_Aranea
{
	my $thing = shift;
	return unless $thing;
	my $t = hex($thing->{st}) if exists $thing->{st};
	$t ||= $thing->{time} / 60;
	my @spot = Spot::prepare(
							 $thing->{f},
							 $thing->{c},
							 $t*60,
							 ($thing->{i} || ''),
							 ($thing->{b} || $thing->{fromuser} || $thing->{user} || $thing->{origin}),
							 ($thing->{o} || $thing->{origin}),
							);
	$thing->{spotdata} = \@spot;
	return $thing;
}

sub gen_DXProt
{
	my $thing = shift;
	unless ($thing->{DXProt}) {
		my $sd = $thing->{spotdata};
		my $hops = $thing->{hops} || DXProt::get_hops(11);
		my $text = $sd->[3] || ' ';
		$text =~ s/\^/%5E/g;
		my $t = $sd->[2];
		$thing->{DXProt} = sprintf "PC11^%.1f^$sd->[1]^%s^%s^$text^$sd->[4]^$sd->[7]^$hops^~", $sd->[0], cldate($t), ztime($t);
	}
	return $thing->{DXProt};
}

sub gen_DXCommandmode
{
	my $thing = shift;
	my $dxchan = shift;
	
	# these are always generated, never cached
	return unless $dxchan->{dx};
	
	my $buf;
	if ($dxchan->{ve7cc}) {
		$buf = VE7CC::dx_spot($dxchan, $thing->{spotdata});
	} else {
		$buf = Spot::format_dx_spot($dxchan, $thing->{spotdata});
		$buf .= "\a\a" if $dxchan->{beep};
		$buf =~ s/\%5E/^/g;
	}
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

	my $spot = $thing->{spotdata};
	if (Spot::dup(@$spot[0..4])) {
		dbg("PCPROT: Duplicate Spot ignored\n") if isdbg('chanerr');
		return;
	}

	# add it 
	Spot::add(@$spot);

	$thing->broadcast($dxchan);
}

sub in_filter
{
	my $thing = shift;
	my $dxchan = shift;
	
	# global spot filtering on INPUT
	if ($dxchan->{inspotsfilter}) {
		my ($filter, $hops) = $dxchan->{inspotsfilter}->it($thing->{spotdata});
		unless ($filter) {
			dbg("PCPROT: Rejected by input spot filter") if isdbg('chanerr');
			return;
		}
	}
	return 1;
}

sub out_filter
{
	my $thing = shift;
	my $dxchan = shift;
	
	# global spot filtering on OUTPUT
	if ($dxchan->{spotsfilter}) {
		my ($filter, $hops) = $dxchan->{spotsfilter}->it($thing->{spotdata});
		unless ($filter) {
			dbg("PCPROT: Rejected by output spot filter") if isdbg('chanerr');
			return;
		}
		$thing->{hops} = $hops if $hops;
	} elsif ($dxchan->{isolate}) {
		return;
	}
	return 1;
}
1;
