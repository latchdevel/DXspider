#!/usr/bin/perl -w
#
# This module was written by Steve Franke K9AN. 
# November, 1999.
# 
# The formulas used in this module 
# are described in: 
# Astronomical Algorithms, Second Edition
# by Jean Meeus, 1998
# Published by Willmann-Bell, Inc.
# P.O. Box 35025, Richmond, Virginia 23235
#
# Atmospheric refraction and parallax are taken into
# account when calculating positions of the sun and moon, 
# and also when calculating the rise and set times.
#
# Copyright (c) 1999 - Steve Franke K9AN
#
# $Id$
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
sub reduce_angle_to_360
{
	my $angle = shift;

	$angle=$angle-int($angle/360)*360;
	$angle=$angle+360 if( $angle < 0 );		
	return $angle;
}
sub sindeg
{
	my $angle_in_degrees = shift;

	return sin($angle_in_degrees*$d2r);
}
sub cosdeg
{
	my $angle_in_degrees = shift;

	return cos($angle_in_degrees*$d2r);
}
sub tandeg
{
	my $angle_in_degrees = shift;

	return tan($angle_in_degrees*$d2r);
}
sub get_az_el
{
	my $H=shift;
	my $delta=shift;
	my $lat=shift;

	my $az=$r2d * atan2( sindeg($H), cosdeg($H)*sindeg($lat)-tandeg($delta)*cosdeg($lat) );
	my $h=$r2d * asin( sindeg($lat)*sindeg($delta)+cosdeg($lat)*cosdeg($delta)*cosdeg($H) );
	return ($az,$h);
}
sub rise_set
{
	my $year = shift;
	my $month = shift;
	my $day = shift;
	my $hr = shift;
	my $min = shift;
	my $lat = shift;
	my $lon = shift;
	my $sun0_moon1=shift;		# 0 for sun, 1 for moon, 2 for venus...

	my ($alpha1,$alpha2,$alpha3,$delta1,$delta2,$delta3);
	my ($m0,$m1,$m2,$theta,$alpha,$delta,$H,$az,$h,$h0,$aznow,$hnow,$corr);
	my ($i,$arg,$argtest,$H0,$alphanow,$deltanow,$distance,$distancenow);
	
	my $julianday=julian_day($year,$month,$day);
	my $tt1 = ($julianday-1-2451545)/36525.;
	my $tt2 = ($julianday-2451545)/36525.;
	my $tt3 = ($julianday+1-2451545)/36525.;
	my $ttnow = ($julianday+$hr/24+$min/24/60-2451545)/36525.;

	my $theta0=280.46061837+360.98564736629*($julianday-2451545.0)+
		0.000387933*$tt2*$tt2-$tt2*$tt2*$tt2/38710000;
	$theta0=reduce_angle_to_360($theta0);

	my $thetanow=280.46061837+360.98564736629*($julianday+$hr/24+$min/24/60-2451545.0)+
		0.000387933*$ttnow*$ttnow-$ttnow*$ttnow*$ttnow/38710000;
	$thetanow=reduce_angle_to_360($thetanow);

	if ( $sun0_moon1 == 0 ) {
		($alpha1, $delta1)=get_sun_alpha_delta($tt1);
		($alpha2, $delta2)=get_sun_alpha_delta($tt2);
		($alpha3, $delta3)=get_sun_alpha_delta($tt3);
		($alphanow, $deltanow)=get_sun_alpha_delta($ttnow);
		$h0=-0.8333;
		$H=$thetanow-$lon-$alphanow;
		$H=reduce_angle_to_360($H);
		($aznow,$hnow)=get_az_el($H,$deltanow,$lat);
		$hnow=$hnow +
			1.02/(tandeg($hnow+10.3/($hnow+5.11)))/60;
	}

	if ( $sun0_moon1 == 1 ) {
		($alpha1, $delta1, $distance)=get_moon_alpha_delta($tt1);
		($alpha2, $delta2, $distance)=get_moon_alpha_delta($tt2);
		($alpha3, $delta3, $distance)=get_moon_alpha_delta($tt3);
		($alphanow, $deltanow, $distancenow)=get_moon_alpha_delta($ttnow);
		$h0=0.7275*$r2d*asin(6378.14/$distancenow)-34./60.;
		$H=$thetanow-$lon-$alphanow;
		$H=reduce_angle_to_360($H);
		($aznow,$hnow)=get_az_el($H,$deltanow,$lat);
		$hnow=$hnow-$r2d*asin(sin(6378.14/$distancenow)*cosdeg($hnow))+
			1.02/(tandeg($hnow+10.3/($hnow+5.11)))/60;
	}

	$arg = (sindeg($h0)-sindeg($lat)*sindeg($delta2))/(cosdeg($lat)*cosdeg($delta2));
	$argtest = tandeg($lat)*tandeg($delta2);

	if ( $argtest < -1. ) {
		return sprintf("Doesn't rise.");
	}
	if ( $argtest > 1. ) {
		return sprintf("Doesn't set.");
	}

	$H0 = acos($arg)*$r2d;
	my $aa=$alpha2-$alpha1;
	my $ba=$alpha3-$alpha2;
	$aa=$aa+360 if ($aa < -180);
	$aa=$aa-360 if ($aa >  180);
	$ba=$ba+360 if ($ba < -180);
	$ba=$ba-360 if ($ba >  180);
	my $ca=$ba-$aa;

	my $ad=$delta2-$delta1;
	my $bd=$delta3-$delta2;
	$ad=$ad+360 if ($ad < -180);
	$ad=$ad-360 if ($ad >  180);
	$bd=$bd+360 if ($bd < -180);
	$bd=$bd-360 if ($bd >  180);
	my $cd=$bd-$ad;

	$m0 = ($alpha2 + $lon - $theta0)/360.;
	$m0=$m0+1 if( $m0 < 0 );
	$m0=$m0-1 if( $m0 > 1 );
 	for ($i=1; $i<=2; $i++) {	
		$theta = $theta0+360.985647*$m0;
		$alpha=$alpha2+$m0*($aa+$ba+$m0*$ca)/2;
		$delta=$delta2+$m0*($ad+$bd+$m0*$cd)/2;
		$H=$theta-$lon-$alpha;
		$H=reduce_angle_to_360($H);
		$H=$H-360 if ($H > 180);
		($az,$h)=get_az_el($H,$delta,$lat);
		$corr=-$H/360;
		$m0=$m0+$corr;
		$m0=$m0+1 if( $m0 < 0 );
		$m0=$m0-1 if( $m0 > 1 );
	}

	$m1 = $m0 - $H0/360.;
	$m1=$m1+1 if( $m1 < 0 );
	$m1=$m1-1 if( $m1 > 1 );
	for ($i=1; $i<=2; $i++) {
		$theta = $theta0+360.985647*$m1;
		$alpha=$alpha2+$m1*($aa+$ba+$m1*$ca)/2;
		$delta=$delta2+$m1*($ad+$bd+$m1*$cd)/2;
		$H=$theta-$lon-$alpha;
		$H=reduce_angle_to_360($H);
		($az,$h)=get_az_el($H,$delta,$lat);
		$corr=($h-$h0)/(360*(cosdeg($delta)*cosdeg($lat)*sindeg($H)));
		$m1=$m1+$corr;
		$m1=$m1+1 if( $m1 < 0 );
		$m1=$m1-1 if( $m1 > 1 );
	}

	$m2 = $m0 + $H0/360.;
	$m2=$m2+1 if( $m2 < 0 );
	$m2=$m2-1 if( $m2 > 1 );
	for ($i=1; $i<=2; $i++) {
		$theta = $theta0+360.985647*$m2;
		$alpha=$alpha2+$m2*($aa+$ba+$m2*$ca)/2;
		$delta=$delta2+$m2*($ad+$bd+$m2*$cd)/2;
		$H=$theta-$lon-$alpha;
		$H=reduce_angle_to_360($H);
		($az,$h)=get_az_el($H,$delta,$lat);
		$corr=($h-$h0)/(360*(cosdeg($delta)*cosdeg($lat)*sindeg($H)));
		$m2 = $m2 + $corr;
		$m2=$m2+1 if( $m2 < 0 );
		$m2=$m2-1 if( $m2 > 1 );
	}
	my ($risehr,$risemin,$sethr,$setmin);
	$risehr=int($m1*24);
	$risemin=($m1*24-int($m1*24))*60+0.5;
	if ( $risemin >= 60 ) {
		$risemin=$risemin-60;
		$risehr=$risehr+1;
	}
	$sethr=int($m2*24);
	$setmin=($m2*24-int($m2*24))*60+0.5;
	if ( $setmin >= 60 ) {
		$setmin=$setmin-60;
		$sethr=$sethr+1;
	}

	if ( $sun0_moon1 == 0 ) {
		return (sprintf("%02d:%02dZ", $risehr,$risemin), sprintf("%02d:%02dZ",$sethr,$setmin),$aznow+180,$hnow);
	}
	if ( $sun0_moon1 == 1 ) {
		return (sprintf("%02d:%02dZ", $risehr,$risemin), sprintf("%02d:%02dZ",$sethr,$setmin), 
				$aznow+180,$hnow, -40*log10($distance/385000) );
	}
}
sub get_moon_alpha_delta 
{
	#
	# Calculate the moon's right ascension and declination
	#
	my $tt=shift;

	my $Lp=218.3164477+481267.88123421*$tt-
		0.0015786*$tt*$tt+$tt*$tt*$tt/538841-$tt*$tt*$tt*$tt/65194000;
	$Lp=reduce_angle_to_360($Lp);

	my $D = 297.8501921+445267.1114034*$tt-0.0018819*$tt*$tt+
		$tt*$tt*$tt/545868.-$tt*$tt*$tt*$tt/113065000.;
	$D=reduce_angle_to_360($D);		

	my $M = 357.5291092 + 35999.0502909*$tt-0.0001536*$tt*$tt+
		$tt*$tt*$tt/24490000.;
	$M=reduce_angle_to_360($M);

	my $Mp = 134.9633964 + 477198.8675055*$tt+0.0087414*$tt*$tt+
		$tt*$tt*$tt/69699-$tt*$tt*$tt*$tt/14712000;
	$Mp=reduce_angle_to_360($Mp);

	my $F = 93.2720950 + 483202.0175233*$tt - 0.0036539*$tt*$tt-
		$tt*$tt*$tt/3526000 + $tt*$tt*$tt*$tt/863310000;
	$F=reduce_angle_to_360($F);

	my $A1 = 119.75 + 131.849 * $tt;
	$A1=reduce_angle_to_360($A1);

	my $A2 =  53.09 + 479264.290 * $tt;
	$A2=reduce_angle_to_360($A2);

	my $A3 = 313.45 + 481266.484 * $tt;
	$A3=reduce_angle_to_360($A3);

	my $E = 1 - 0.002516 * $tt - 0.0000074 * $tt * $tt;

	my $Sl=  6288774*sindeg(                  1 * $Mp          ) +
		 1274027*sindeg(2 * $D +         -1 * $Mp          ) +
		 658314 *sindeg(2 * $D                             ) +
		 213618 *sindeg(                  2 * $Mp          ) +
		-185116 *sindeg(         1 * $M                    )*$E +
		-114332 *sindeg(                            2 * $F ) +
		  58793 *sindeg(2 * $D +         -2 * $Mp          ) +
		  57066 *sindeg(2 * $D - 1 * $M  -1 * $Mp          )*$E +
		  53322 *sindeg(2 * $D +          1 * $Mp          ) +
		  45758 *sindeg(2 * $D - 1 * $M                    )*$E +
		 -40923 *sindeg(       + 1 * $M  -1 * $Mp          )*$E +
		 -34720 *sindeg(1 * $D                             ) +
		 -30383 *sindeg(       + 1 * $M + 1 * $Mp          )*$E +
		  15327 *sindeg(2 * $D +                   -2 * $F ) +
		 -12528 *sindeg(                  1 * $Mp + 2 * $F ) +
		  10980 *sindeg(                  1 * $Mp - 2 * $F ) +
		  10675 *sindeg(4 * $D +         -1 * $Mp          ) +
		  10034 *sindeg(                  3 * $Mp          ) +
		   8548 *sindeg(4 * $D + 0 * $M - 2 * $Mp + 0 * $F ) +
		  -7888 *sindeg(2 * $D + 1 * $M - 1 * $Mp + 0 * $F )*$E +
		  -6766 *sindeg(2 * $D + 1 * $M + 0 * $Mp + 0 * $F )*$E +
		  -5163 *sindeg(1 * $D + 0 * $M - 1 * $Mp + 0 * $F ) +
		   4987 *sindeg(1 * $D + 1 * $M + 0 * $Mp + 0 * $F )*$E +
		   4036 *sindeg(2 * $D - 1 * $M + 1 * $Mp + 0 * $F )*$E +
		   3994 *sindeg(2 * $D + 0 * $M + 2 * $Mp + 0 * $F ) +
		   3861 *sindeg(4 * $D + 0 * $M + 0 * $Mp + 0 * $F ) +
		   3665 *sindeg(2 * $D + 0 * $M - 3 * $Mp + 0 * $F ) +
		  -2689 *sindeg(0 * $D + 1 * $M - 2 * $Mp + 0 * $F )*$E +
		  -2602 *sindeg(2 * $D + 0 * $M - 1 * $Mp + 2 * $F ) +
		   2390 *sindeg(2 * $D - 1 * $M - 2 * $Mp + 0 * $F )*$E +
		  -2348 *sindeg(1 * $D + 0 * $M + 1 * $Mp + 0 * $F ) +
		   2236 *sindeg(2 * $D - 2 * $M + 0 * $Mp + 0 * $F )*$E*$E +
		  -2120 *sindeg(0 * $D + 1 * $M + 2 * $Mp + 0 * $F )*$E +
		  -2069 *sindeg(0 * $D + 2 * $M + 0 * $Mp + 0 * $F )*$E*$E +
		   2048 *sindeg(2 * $D - 2 * $M - 1 * $Mp + 0 * $F )*$E*$E +
		  -1773 *sindeg(2 * $D + 0 * $M + 1 * $Mp - 2 * $F ) +
		  -1595 *sindeg(2 * $D + 0 * $M + 0 * $Mp + 2 * $F ) +
		   1215 *sindeg(4 * $D - 1 * $M - 1 * $Mp + 0 * $F )*$E +
		  -1110 *sindeg(0 * $D + 0 * $M + 2 * $Mp + 2 * $F ) +
		   -892 *sindeg(3 * $D + 0 * $M - 1 * $Mp + 0 * $F ) +
		   -810 *sindeg(2 * $D + 1 * $M + 1 * $Mp + 0 * $F )*$E +
		    759 *sindeg(4 * $D - 1 * $M - 2 * $Mp + 0 * $F )*$E +
		   -713 *sindeg(0 * $D + 2 * $M - 1 * $Mp + 0 * $F )*$E*$E +
		   -700 *sindeg(2 * $D + 2 * $M - 1 * $Mp + 0 * $F )*$E*$E +
		    691 *sindeg(2 * $D + 1 * $M - 2 * $Mp + 0 * $F )*$E +
		    596 *sindeg(2 * $D - 1 * $M + 0 * $Mp - 2 * $F )*$E +
		    549 *sindeg(4 * $D + 0 * $M + 1 * $Mp + 0 * $F ) +
		    537 *sindeg(0 * $D + 0 * $M + 4 * $Mp + 0 * $F ) +
		    520 *sindeg(4 * $D - 1 * $M + 0 * $Mp + 0 * $F )*$E +
		   -487 *sindeg(1 * $D + 0 * $M - 2 * $Mp + 0 * $F ) +
		   -399 *sindeg(2 * $D + 1 * $M + 0 * $Mp - 2 * $F )*$E +
		   -381 *sindeg(0 * $D + 0 * $M + 2 * $Mp - 2 * $F ) +
		    351 *sindeg(1 * $D + 1 * $M + 1 * $Mp + 0 * $F )*$E +
		   -340 *sindeg(3 * $D + 0 * $M - 2 * $Mp + 0 * $F ) +
		    330 *sindeg(4 * $D + 0 * $M - 3 * $Mp + 0 * $F ) +
		    327 *sindeg(2 * $D - 1 * $M + 2 * $Mp + 0 * $F )*$E +
		   -323 *sindeg(0 * $D + 2 * $M + 1 * $Mp + 0 * $F )*$E*$E +
		    299 *sindeg(1 * $D + 1 * $M - 1 * $Mp + 0 * $F )*$E +
		    294 *sindeg(2 * $D + 0 * $M + 3 * $Mp + 0 * $F ) +
		   3958 *sindeg($A1) + 1962*sindeg($Lp - $F) + 318*sindeg($A2);

	my $Sr=-20905355 *cosdeg(                   1 * $Mp          ) +
		-3699111 *cosdeg(2 * $D +          -1 * $Mp          ) +
		-2955968 *cosdeg(2 * $D                              ) +
		 -569925 *cosdeg(                   2 * $Mp          ) +
		   48888 *cosdeg(         1 * $M                     )*$E +
		   -3149 *cosdeg(                             2 * $F ) + 
	  	  246158 *cosdeg(2 * $D +          -2 * $Mp           ) +
		 -152138 *cosdeg(2 * $D - 1 * $M   -1 * $Mp           )*$E +
		 -170733 *cosdeg(2 * $D +           1 * $Mp           ) +
		 -204586 *cosdeg(2 * $D - 1 * $M                      )*$E +
		 -129620 *cosdeg(       + 1 * $M   -1 * $Mp           )*$E +
		  108743 *cosdeg(1 * $D                              ) +
		  104755 *cosdeg(       + 1 * $M  + 1 * $Mp           )*$E +
		  10321 *cosdeg(2 * $D +                     -2 * $F ) +
		  79661 *cosdeg(                   1 * $Mp -  2 * $F ) +
		 -34782 *cosdeg(4 * $D +          -1 * $Mp           ) +
		 -23210 *cosdeg(                   3 * $Mp           ) +
		 -21636 *cosdeg(4 * $D + 0 * $M - 2 * $Mp + 0 * $F ) +
		  24208 *cosdeg(2 * $D + 1 * $M - 1 * $Mp + 0 * $F )*$E +
		  30824 *cosdeg(2 * $D + 1 * $M + 0 * $Mp + 0 * $F )*$E +
		  -8379 *cosdeg(1 * $D + 0 * $M - 1 * $Mp + 0 * $F ) +
		 -16675 *cosdeg(1 * $D + 1 * $M + 0 * $Mp + 0 * $F )*$E +
		 -12831 *cosdeg(2 * $D - 1 * $M + 1 * $Mp + 0 * $F )*$E +
		 -10445 *cosdeg(2 * $D + 0 * $M + 2 * $Mp + 0 * $F ) +
		 -11650 *cosdeg(4 * $D + 0 * $M + 0 * $Mp + 0 * $F ) +
		  14403 *cosdeg(2 * $D + 0 * $M - 3 * $Mp + 0 * $F ) +
		  -7003 *cosdeg(0 * $D + 1 * $M - 2 * $Mp + 0 * $F )*$E +
		  10056 *cosdeg(2 * $D - 1 * $M - 2 * $Mp + 0 * $F )*$E +
		   6322 *cosdeg(1 * $D + 0 * $M + 1 * $Mp + 0 * $F ) +
		  -9884 *cosdeg(2 * $D - 2 * $M + 0 * $Mp + 0 * $F )*$E*$E +
		   5751 *cosdeg(0 * $D + 1 * $M + 2 * $Mp + 0 * $F )*$E +
		  -4950 *cosdeg(2 * $D - 2 * $M - 1 * $Mp + 0 * $F )*$E*$E +
		   4130 *cosdeg(2 * $D + 0 * $M + 1 * $Mp - 2 * $F )+
		  -3958 *cosdeg(4 * $D - 1 * $M - 1 * $Mp + 0 * $F )*$E +
		   3258 *cosdeg(3 * $D + 0 * $M - 1 * $Mp + 0 * $F )+
		   2616 *cosdeg(2 * $D + 1 * $M + 1 * $Mp + 0 * $F )*$E +
		  -1897 *cosdeg(4 * $D - 1 * $M - 2 * $Mp + 0 * $F )*$E +
		  -2117 *cosdeg(0 * $D + 2 * $M - 1 * $Mp + 0 * $F )*$E*$E +
		   2354 *cosdeg(2 * $D + 2 * $M - 1 * $Mp + 0 * $F )*$E*$E +
		  -1423 *cosdeg(4 * $D + 0 * $M + 1 * $Mp + 0 * $F )+
		  -1117 *cosdeg(0 * $D + 0 * $M + 4 * $Mp + 0 * $F )+
		  -1571 *cosdeg(4 * $D - 1 * $M + 0 * $Mp + 0 * $F )*$E +
		  -1739 *cosdeg(1 * $D + 0 * $M - 2 * $Mp + 0 * $F )+
		  -4421 *cosdeg(0 * $D + 0 * $M + 2 * $Mp - 2 * $F )+
		   1165 *cosdeg(0 * $D + 2 * $M + 1 * $Mp + 0 * $F )*$E*$E +
		   8752 *cosdeg(2 * $D + 0 * $M - 1 * $Mp - 2 * $F );

	my $Sb=  5128122 *sindeg(                            1 * $F  ) +
		  280602 *sindeg(                  1 * $Mp + 1 * $F  ) +
		  277693 *sindeg(                  1 * $Mp - 1 * $F  ) +
		  173237 *sindeg(2 * $D                    - 1 * $F  ) +
		   55413 *sindeg(2 * $D           -1 * $Mp + 1 * $F  ) +
		   46271 *sindeg(2 * $D +         -1 * $Mp - 1 * $F  ) +
		   32573 *sindeg(2 * $D +                    1 * $F  ) +
		   17198 *sindeg(                  2 * $Mp + 1 * $F  )+
		    9266 *sindeg(2 * $D + 0 * $M + 1 * $Mp - 1 * $F ) +
		    8822 *sindeg(0 * $D + 0 * $M + 2 * $Mp - 1 * $F ) +
		    8216 *sindeg(2 * $D - 1 * $M + 0 * $Mp - 1 * $F )*$E +
		    4324 *sindeg(2 * $D + 0 * $M - 2 * $Mp - 1 * $F ) +
		    4200 *sindeg(2 * $D + 0 * $M + 1 * $Mp + 1 * $F ) +
		   -3359 *sindeg(2 * $D + 1 * $M + 0 * $Mp - 1 * $F )*$E +
		    2463 *sindeg(2 * $D - 1 * $M - 1 * $Mp + 1 * $F )*$E +
		    2211 *sindeg(2 * $D - 1 * $M + 0 * $Mp + 1 * $F )*$E +
		    2065 *sindeg(2 * $D - 1 * $M - 1 * $Mp - 1 * $F )*$E +
		   -1870 *sindeg(0 * $D + 1 * $M - 1 * $Mp - 1 * $F )*$E +
		    1828 *sindeg(4 * $D + 0 * $M - 1 * $Mp - 1 * $F ) +
		   -1794 *sindeg(0 * $D + 1 * $M + 0 * $Mp + 1 * $F )*$E +
		   -1749 *sindeg(0 * $D + 0 * $M + 0 * $Mp + 3 * $F ) +
		   -1565 *sindeg(0 * $D + 1 * $M - 1 * $Mp + 1 * $F )*$E +
		   -1491 *sindeg(1 * $D + 0 * $M + 0 * $Mp + 1 * $F ) +
		   -1475 *sindeg(0 * $D + 1 * $M + 1 * $Mp + 1 * $F )*$E +
		   -1410 *sindeg(0 * $D + 1 * $M + 1 * $Mp - 1 * $F )*$E +
		   -1344 *sindeg(0 * $D + 1 * $M + 0 * $Mp - 1 * $F )*$E +
		   -1335 *sindeg(1 * $D + 0 * $M + 0 * $Mp - 1 * $F ) +
		    1107 *sindeg(0 * $D + 0 * $M + 3 * $Mp + 1 * $F ) +
		    1021 *sindeg(4 * $D + 0 * $M + 0 * $Mp - 1 * $F ) +
		     833 *sindeg(4 * $D + 0 * $M - 1 * $Mp + 1 * $F ) +
		     777 *sindeg(0 * $D + 0 * $M + 1 * $Mp - 3 * $F ) +
		     671 *sindeg(4 * $D + 0 * $M - 2 * $Mp + 1 * $F ) +
		     607 *sindeg(2 * $D + 0 * $M + 0 * $Mp - 3 * $F ) +
		     596 *sindeg(2 * $D + 0 * $M + 2 * $Mp - 1 * $F ) +
		     491 *sindeg(2 * $D - 1 * $M + 1 * $Mp - 1 * $F )*$E +
		    -451 *sindeg(2 * $D + 0 * $M - 2 * $Mp + 1 * $F ) +
		     439 *sindeg(0 * $D + 0 * $M + 3 * $Mp - 1 * $F ) +
		     422 *sindeg(2 * $D + 0 * $M + 2 * $Mp + 1 * $F ) +
		     421 *sindeg(2 * $D + 0 * $M - 3 * $Mp - 1 * $F ) +
		    -366 *sindeg(2 * $D + 1 * $M - 1 * $Mp + 1 * $F )*$E +
		    -351 *sindeg(2 * $D + 1 * $M + 0 * $Mp + 1 * $F )*$E +
		     331 *sindeg(4 * $D + 0 * $M + 0 * $Mp + 1 * $F ) +
		     315 *sindeg(2 * $D - 1 * $M + 1 * $Mp + 1 * $F )*$E +
		     302 *sindeg(2 * $D - 2 * $M + 0 * $Mp - 1 * $F )*$E*$E +
		    -283 *sindeg(0 * $D + 0 * $M + 1 * $Mp + 3 * $F ) +
		    -229 *sindeg(2 * $D + 1 * $M + 1 * $Mp - 1 * $F )*$E +
		     223 *sindeg(1 * $D + 1 * $M + 0 * $Mp - 1 * $F )*$E +
		     223 *sindeg(1 * $D + 1 * $M + 0 * $Mp + 1 * $F )*$E +
		    -220 *sindeg(0 * $D + 1 * $M - 2 * $Mp - 1 * $F )*$E +
		    -220 *sindeg(2 * $D + 1 * $M - 1 * $Mp - 1 * $F )*$E +
		    -185 *sindeg(1 * $D + 0 * $M + 1 * $Mp + 1 * $F ) +
		     181 *sindeg(2 * $D - 1 * $M - 2 * $Mp - 1 * $F )*$E +
		    -177 *sindeg(0 * $D + 1 * $M + 2 * $Mp + 1 * $F )*$E +
		     176 *sindeg(4 * $D + 0 * $M - 2 * $Mp - 1 * $F ) +
		     166 *sindeg(4 * $D - 1 * $M - 1 * $Mp - 1 * $F )*$E +
		    -164 *sindeg(1 * $D + 0 * $M + 1 * $Mp - 1 * $F ) +
		     132 *sindeg(4 * $D + 0 * $M + 1 * $Mp - 1 * $F ) +
		    -119 *sindeg(1 * $D + 0 * $M - 1 * $Mp - 1 * $F ) +
		     115 *sindeg(4 * $D - 1 * $M + 0 * $Mp - 1 * $F )*$E +
		     107 *sindeg(2 * $D - 2 * $M + 0 * $Mp + 1 * $F )*$E*$E  
		   -2235 *sindeg($Lp) + 382*sindeg($A3) + 
	 	     175 *sindeg($A1-$F) + 175*sindeg($A1+$F) +
		     127 *sindeg($Lp-$Mp) - 115*sindeg($Lp+$Mp);
 
	my $lambda=$Lp+$Sl/1000000.; 

	my $beta=$Sb/1000000.;

	my $distance=385000.56 + $Sr/1000.;

	my $epsilon = 23+26./60.+21.448/(60.*60.);

	my $alpha=atan2(cosdeg($epsilon)*sindeg($lambda)-tandeg($beta)*sindeg($epsilon),cosdeg($lambda))*$r2d;
	$alpha = reduce_angle_to_360($alpha);

	my $delta=asin(cosdeg($beta)*sindeg($epsilon)*sindeg($lambda)+sindeg($beta)*cosdeg($epsilon))*$r2d;
	$delta = reduce_angle_to_360($delta);

	return ($alpha,$delta,$distance);
}
 
sub get_sun_alpha_delta 
{
	#
	# Calculate Sun's right ascension and declination
	#
	my $tt = shift;

	my $L0 = 280.46646+36000.76983*$tt+0.0003032*($tt^2);
	$L0=reduce_angle_to_360($L0);

	my $M = 357.52911 + 35999.05029*$tt-0.0001537*($tt^2);
	$M=reduce_angle_to_360($M);

	my $C = (1.914602 - 0.004817*$tt-0.000014*($tt^2))*sindeg($M) +
		(0.019993 - 0.000101*$tt)*sindeg(2*$M) +
	        0.000289*sindeg(3*$M);

	my $OMEGA = 125.04 - 1934.136*$tt;
	
	my $lambda=$L0+$C-0.00569-0.00478*sindeg($OMEGA); 

	my $epsilon = 23+26./60.+21.448/(60.*60.);

	my $alpha=atan2(cosdeg($epsilon)*sindeg($lambda),cosdeg($lambda))*$r2d;
	$alpha = reduce_angle_to_360($alpha);

	my $delta=asin(sin($epsilon*$d2r)*sin($lambda*$d2r))*$r2d;
	$delta = reduce_angle_to_360($delta);

	return ($alpha,$delta);
}

