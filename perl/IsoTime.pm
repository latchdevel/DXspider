#
# Utility routines for handling Iso 8601 date time groups
#
#
#
# Copyright (c) Dirk Koopman, G1TLH
#

use strict;

package IsoTime;

use Date::Parse;

use vars qw($year $month $day $hour $min $sec @days @ldays);
@days = (31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31);
@ldays = (31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31);

# is it a leap year?
sub _isleap
{
	my $year = shift;
	return ($year % 4 == 0 && ($year % 100 != 0 || $year % 400 == 0)) ? 1 : 0; 
}

sub full
{
	return sprintf "%04d%02d%02dT%02d%02d%02d", $year, $month, $day, $hour, $min, $sec; 
}

sub dayminsec
{
	return sprintf "%02dT%02d%02d%02d", $day, $hour, $min, $sec; 
}

sub daymin
{
	return sprintf "%02dT%02d%02d", $day, $hour, $min; 
}

sub hourmin
{
	return sprintf "%02d%02d", $hour, $min; 

}

sub hourminsec
{
	return sprintf "%02d%02d%02d", $hour, $min, $sec; 
}

sub update
{
	my $t = shift || time;
	($sec,$min,$hour,$day,$month,$year) = gmtime($t);
	$month++;
	$year += 1900;
}

sub unixtime
{
	my $iso = shift;

	# get the correct day, if required
	if (my ($h) = $iso =~ /^([012]\d)[0-5]\d(?:[0-5]\d)?$/) {
		my ($d, $m, $y) = ($day, $month, $year);
		if ($h != $hour) {
			if ($hour < 12 && $h - $hour >= 12) {
				# yesterday
				($d, $m, $y) = _yesterday($d, $m, $y);
			} elsif ($hour >= 12 && $hour - $h > 12) {
				# tomorrow
				($d, $m, $y) = _tomorrow($d, $m, $y);
			}
		}
		$iso = sprintf("%04d%02d%02dT", $y, $m, $d) . $iso;
	} elsif (my ($d) = $iso =~ /^(\d\d)T\d\d\d\d/) {

		# get the correct month and year if it is a short date
		if ($d == $day) {
			$iso = sprintf("%04d%02d", $year, $month) . $iso;
		} else {
			my $days = _isleap($year) ? $ldays[$month-1] : $days[$month-1];
			my ($y, $m) = ($year, $month);
			if ($d < $day) {
				if ($day - $d > $days / 2) {
					if ($month == 1) {
						$y = $year - 1;
						$m = 12;
					} else {
						$m = $month - 1;
					}
				} 
			} else {
				if ($d - $day > $days / 2) {
					if ($month == 12) {
						$y = $year + 1;
						$m = 1;
					} else {
						$m = $month + 1;
					}
				}
			}
			$iso = sprintf("%04d%02d", $y, $m) . $iso;
		}
	} 
		
	return str2time($iso);
}

sub _tomorrow
{
	my ($d, $m, $y) = @_;

	$d++;
	my $days = _isleap($y) ? $ldays[$month-1] : $days[$month-1];
	if ($d > $days) {
		$d = 1;
		$m++;
		if ($m > 12) {
			$m = 1;
			$y++;
		} else {
			$y = $year;
		}
	}

	return ($d, $m, $y);
}

sub _yesterday
{
	my ($d, $m, $y) = @_;

	$d--;
	if ($d <= 0) {
		$m--;
		$y = $year;
		if ($m <= 0) {
			$m = 12;
			$y--;
		}
		$d = _isleap($y) ? $ldays[$m-1] : $days[$m-1];
	}

	return ($d, $m, $y);
}
1;
