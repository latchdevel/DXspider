#
# various julian date calculations
#
# Copyright (c) - 1998 Dirk Koopman G1TLH
#
# $Id$
#

package Julian;

use Carp;

use strict;

my @days = (31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31);

# take a unix date and transform it into a julian day (ie (1998, 13) = 13th day of 1998)
sub unixtoj
{
	my $t = shift;
	my ($year, $day) = (gmtime($t))[5,7];
	
	$year += 1900;
	return ($year, $day+1);
}

# take a unix and return a julian month from it
sub unixtojm
{
	my $t = shift;
	my ($mon, $year) = (gmtime($t))[4..5];

	$year += 1900;
	return ($year, $mon + 1);
}

# take a julian date and subtract a number of days from it, returning the julian date
sub sub
{
	my ($year, $day, $amount) = @_;
	my $diny = isleap($year) ? 366 : 365;
	$day -= $amount;
	while ($day <= 0) {
		$day += $diny;
		$year -= 1;
		$diny = isleap($year) ? 366 : 365;
	}
	return ($year, $day);
}

sub add
{
	my ($year, $day, $amount) = @_;
	my $diny = isleap($year) ? 366 : 365;
	$day += $amount;
	while ($day > $diny) {
		$day -= $diny;
		$year += 1;
		$diny = isleap($year) ? 366 : 365;
	}
	return ($year, $day);
} 

# take a julian month and subtract a number of months from it, returning the julian month
sub subm
{
	my ($year, $mon, $amount) = @_;
	$mon -= $amount;
	while ($mon <= 0) {
		$mon += 12;
		$year -= 1;
	}
	return ($year, $mon);
}

sub addm
{
	my ($year, $mon, $amount) = @_;
	$mon += $amount;
	while ($mon > 12) {
		$mon -= 12;
		$year += 1;
	}
	return ($year, $mon);
} 

sub cmp
{
	my ($y1, $d1, $y2, $d2) = @_;
	return $d1 - $d2 if ($y1 == $y2);
	return $y1 - $y2;
}

# is it a leap year?
sub isleap
{
	my $year = shift;
	return ($year % 4 == 0 && ($year % 100 != 0 || $year % 400 == 0)) ? 1 : 0; 
}


1;
