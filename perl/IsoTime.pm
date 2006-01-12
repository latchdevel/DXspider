#
# Utility routines for handling Iso 8601 date time groups
#
# $Id$
#
# Copyright (c) Dirk Koopman, G1TLH
#

use strict;

package IsoTime;

use Date::Parse;

use vars qw($VERSION $BRANCH $year $month $day $hour $min $sec @days @ldays);
$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /\d+\.\d+\.(\d+)\.(\d+)/  || (0,0));
$main::build += $VERSION;
$main::branch += $BRANCH;

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
	
	# get the correct month and year if it is a short date
	if (my ($d) = $iso =~ /^(\d\d)T\d\d\d\d/) {
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
1;