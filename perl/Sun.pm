#!/usr/bin/perl -w
#
# The subroutines "julian_day" and "riseset" written by 
# Steve Franke, November 1999.
# 
# The formulas used to calculate sunrise and sunset times
# are described in Chapters 7, 12, 15, and 25 of
# Astronomical Algorithms, Second Edition
# by Jean Meeus, 1998
# Published by Willmann-Bell, Inc.
# P.O. Box 35025, Richmond, Virginia 23235
#
package Sun;

use POSIX;

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw($pi $d2r $r2d );

use strict;
use vars qw($pi $d2r $r2d );

$pi = 3.141592653589;
$d2r = ($pi/180);
$r2d = (180/$pi);

sub julian_day
{
	my $year = shift;
	my $month = shift;
	my $day = shift;
	my $julianday;
	
	$year=$year-1 if( $month <= 2 );
	$month=$month+12 if( $month <= 2);
	
	$julianday = int(365.25*($year+4716)+int(30.6001*($month+1)))+$day-13-1524.5;
	return $julianday;
}

sub riseset
{
	my $year = shift;
	my $month = shift;
	my $day = shift;
	my $lat = shift;
	my $lon = shift;
	my $julianday;
	
	$julianday=julian_day($year,$month,$day);
	
	my $tt = ($julianday-2451545)/36525.;
	
	my $theta0=280.46061837+360.98564736629*($julianday-2451545.0)+
		0.000387933*($tt^2)-($tt^3)/38710000;
	$theta0=$theta0-int($theta0/360)*360;
	$theta0=$theta0+360 if( $theta0 < 0 );		
	
	my $L0 = 280.46646+36000.76983*$tt+0.0003032*($tt^2);
	$L0=$L0-int($L0/360)*360;
	$L0=$L0+360 if( $L0 < 0 );		
	
	my $M = 357.52911 + 35999.05029*$tt-0.0001537*($tt^2);
	$M=$M-int($M/360)*360;
	$M=$M+360 if( $M < 0 );		
	
	my $C = (1.914602 - 0.004817*$tt-0.000014*($tt^2))*sin($M*$d2r) +
		(0.019993 - 0.000101*$tt)*sin(2*$M*$d2r) +
	        0.000289*sin(3*$M*$d2r);
	
	my $OMEGA = 125.04 - 1934.136*$tt;
	
	my $lambda=$L0+$C-0.00569-0.00478*sin($OMEGA*$d2r); 
	
	my $epsilon = 23+26./60.+21.448/(60.*60.);
	
	my $alpha=atan2(cos($epsilon*$d2r)*sin($lambda*$d2r),cos($lambda*$d2r))*$r2d;
	$alpha = $alpha-int($alpha/360)*360;
	$alpha=$alpha+360 if ( $alpha < 0 );
	
	my $delta=asin(sin($epsilon*$d2r)*sin($lambda*$d2r))*$r2d;
	$delta = $delta-int($delta/360)*360;
	$delta = $delta+360 if ( $delta < 0 );
	
	my $arg = (sin(-.8333*$d2r)-sin($lat)*sin($delta*$d2r))/(cos($lat)*cos($delta*$d2r));
	my $argtest = tan($lat)*tan($delta*$d2r);
	
	if ( $argtest < -1. ) {
		return sprintf("Sun doesn't rise.");
	}
	if ( $argtest > 1. ) {
		return sprintf("Sun doesn't set.");
	}
	
	my $H0 = acos($arg)*$r2d;
	
	my $transit = ($alpha + $lon*$r2d - $theta0)/360.;
	$transit=$transit+1 if( $transit < 0 );
	$transit=$transit-1 if( $transit > 1 );
	
	my $rise = $transit - $H0/360.;
	$rise=$rise+1 if( $rise < 0 );
	$rise=$rise-1 if( $rise > 1 );
	
	my $set = $transit + $H0/360.;
	$set=$set+1 if( $set < 0 );
	$set=$set-1 if( $set > 1 );
	
	return sprintf("Sunrise: %2.2d%2.2dZ   Sunset: %2.2d%2.2dZ",int($rise*24),
				   ($rise*24-int($rise*24))*60.,
				   int($set*24),($set*24-int($set*24))*60.);
}

1;
