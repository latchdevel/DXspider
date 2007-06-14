#
# various julian date calculations
#
# Copyright (c) - 1998 Dirk Koopman G1TLH
#
# $Id$
#

use strict;

package Julian;


use vars qw(@days @ldays @month);
@days = (31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31);
@ldays = (31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31);
@month = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);

sub alloc($$$)
{
	my ($pkg, $year, $thing) = @_;
	return bless [$year, $thing], ref($pkg)||$pkg;
}

sub copy
{
	my $old = shift;
	return $old->alloc(@$old);
}

sub cmp($$)
{
	my ($a, $b) = @_;
	return $a->[1] - $b->[1] if ($a->[0] == $b->[0]);
	return $a->[0] - $b->[0];
}

sub year
{
	return $_[0]->[0];
}

sub thing
{
	return $_[0]->[1];
}

package Julian::Day;

use vars qw(@ISA);
@ISA = qw(Julian);

# is it a leap year?
sub _isleap
{
	my $year = shift;
	return ($year % 4 == 0 && ($year % 100 != 0 || $year % 400 == 0)) ? 1 : 0; 
}

sub new($$)
{
	my $pkg = shift;
	my $t = shift;
	my ($year, $day) = (gmtime($t))[5,7];
	$year += 1900;
	return $pkg->SUPER::alloc($year, $day+1);
}

# take a julian date and subtract a number of days from it, returning the julian date
sub sub($$)
{
	my ($old, $amount) = @_;
	my $self = $old->copy;
	my $diny = _isleap($self->[0]) ? 366 : 365;
	$self->[1] -= $amount;
	while ($self->[1] <= 0) {
		$self->[0] -= 1;
		$diny = _isleap($self->[0]) ? 366 : 365;
		$self->[1] += $diny;
	}
	return $self;
}

sub add($$)
{
	my ($old, $amount) = @_;
	my $self = $old->copy;
	my $diny = _isleap($self->[0]) ? 366 : 365;
	$self->[1] += $amount;
	while ($self->[1] > $diny) {
		$self->[1] -= $diny;
		$self->[0] += 1;
		$diny = _isleap($self->[0]) ? 366 : 365;
	}
	return $self;
} 

sub as_string
{
	my $self = shift;
	my $days = $self->[1];
	my $mon = 0;
	for (_isleap($self->[0]) ? @Julian::ldays : @Julian::days) {
		if ($_ < $days) {
			$days -= $_;
			$mon++;
		} else {
			last;
		}
	}
	return "$days-$Julian::month[$mon]-$self->[0]";
}

package Julian::Month;

use vars qw(@ISA);
@ISA = qw(Julian);

sub new($$)
{
	my $pkg = shift;
	my $t = shift;
	my ($mon, $year) = (gmtime($t))[4,5];
	$year += 1900;
	return $pkg->SUPER::alloc($year, $mon+1);
}

# take a julian month and subtract a number of months from it, returning the julian month
sub sub($$)
{
	my ($old, $amount) = @_;
	my $self = $old->copy;
	
	$self->[1] -= $amount;
	while ($self->[1] <= 0) {
		$self->[1] += 12;
		$self->[0] -= 1;
	}
	return $self;
}

sub add($$)
{
	my ($old, $amount) = @_;
	my $self = $old->copy;

	$self->[1] += $amount;
	while ($self->[1] > 12) {
		$self->[1] -= 12;
		$self->[0] += 1;
	}
	return $self;
} 

sub as_string
{
	my $self = shift;
	return "$Julian::month[$self->[1]]-$self->[0]";
}


1;
