#
# Thingy Route Filter handling
#
# This to provide multiple inheritance to Routing entities
# that wish to do standard filtering
#
# $Id$
#
# Copyright (c) 2005 Dirk Koopman G1TLH
#

use strict;

package Thingy::RouteFilter;

use vars qw($VERSION $BRANCH);

main::mkver($VERSION = q$Revision$);

use DXChannel;
use DXDebug;
use DXProt;
use Thingy;

use vars qw(@ISA);
@ISA = qw(Thingy);

sub _filter
{
	my $dxchan = shift;
	my @out;
	
	foreach my $r (@_) {
		my ($filter, $hops) = $dxchan->{routefilter}->it($dxchan->{call}, $dxchan->{dxcc}, $dxchan->{itu}, $dxchan->{cq}, $r->{call}, $r->{dxcc}, $r->{itu}, $r->{cq}, $dxchan->{state}, $r->{state});
		push @out, $r if $filter;
	}
	return @out;
}

sub gen_DXProt
{
	my $thing = shift;
	my @out;
	push @out, DXProt::pc21(@{$thing->{fpc21n}}) if $thing->{fpc21n};
	push @out, DXProt::pc17($thing->{fpc17n}, @{$thing->{pc17u}})  if $thing->{fpc17n};
	push @out, DXProt::pc19(@{$thing->{fpc19n}}) if $thing->{fpc19n};
	push @out, DXProt::pc16($thing->{fpc16n}, @{$thing->{pc16u}}) if $thing->{fpc16n};
	return \@out;
}

sub in_filter
{
	my $thing = shift;
	my $dxchan = shift;
	
	# global route filtering on INPUT
	if ($dxchan->{inroutefilter}) {
		my $r = Route::Node::get($thing->{origin}) || Route->new($thing->{origin});
		my ($filter, $hops) = $dxchan->{inroutefilter}->it($dxchan->{call}, $dxchan->{dxcc}, $dxchan->{itu}, $dxchan->{cq}, $r->{call}, $r->{dxcc}, $r->{itu}, $r->{cq}, $dxchan->{state}, $r->{state});
		unless ($filter) {
			dbg("PCPROT: Rejected by input route filter") if isdbg('chanerr');
			return;
		}
	} elsif ($dxchan->{isolate} && $thing->{origin} ne $main::mycall) {
		return;
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
		
		if ($dxchan->isa('DXProt')) {
			$thing->{hops} = $hops if $hops;
			delete $thing->{fpc16n};
			delete $thing->{fpc17n};
			delete $thing->{fpc19n};
			delete $thing->{fpc21n};
	
			$thing->{fpc16n} = _filter($dxchan, $thing->{pc16n}) if $thing->{pc16n};
			$thing->{fpc17n} = _filter($dxchan, $thing->{pc17n}) if $thing->{pc17n};
			my @pc19 = _filter($dxchan, @{$thing->{pc19n}}) if $thing->{pc19n};
			$thing->{fpc19n} = \@pc19 if @pc19;
			my @pc21 = _filter($dxchan, @{$thing->{pc21n}}) if $thing->{pc21n};
			$thing->{fpc21n} = \@pc21 if @pc21;
		}
		return 1;
		
	} elsif ($dxchan->{isolate}) {
		return if $thing->{origin} ne $main::mycall;
	}
	if ($dxchan->isa('DXProt')) {
		$thing->{fpc16n} ||= $thing->{pc16n}; 
		$thing->{fpc17n} ||= $thing->{pc17n}; 
		$thing->{fpc19n} ||= $thing->{pc18n}; 
		$thing->{fpc21n} ||= $thing->{pc21n}; 
	}
	return 1;
}

1;
