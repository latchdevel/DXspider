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
use vars qw($pi $d2r $r2d);
 
$pi = 3.141592653589;
$d2r = ($pi/180);
$r2d = (180/$pi);

use vars qw(%keps);
use Keps;
use DXVars;
use DXUtil;

# reload the keps data
sub load
{
	my @out;
	my $s = readfilestr("$main::root/local/Keps.pm");
	if ($s) {
		eval $s;
		push @out, $@ if $@;
	}
    return @out;
}

sub Julian_Day
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
sub Julian_Date_of_Epoch
{
	my $epoch=shift;
	my $year=int($epoch*1e-3);
	$year=$year+2000 if ($year < 57);
	$year=$year+1900 if ($year >= 57);
	my $day=$epoch-$year*1e3;
	my $Julian_Date_of_Epoch=Julian_Date_of_Year($year)+$day;
	return $Julian_Date_of_Epoch;
}
sub Julian_Date_of_Year
{
	my $year=shift;
	$year=$year-1;
	my $A=int($year/100);
	my $B=2-$A+int($A/4);
	my $Julian_Date_of_Year=int(365.25*$year)+int(30.6001*14)+
		1720994.5+$B;
	return $Julian_Date_of_Year;
}	
sub ThetaG_JD
{
	my $jd=shift;
	my $omega_E=1.00273790934; # earth rotations per sidereal day
	my $secday=86400;
	my $UT=($jd+0.5)-int($jd+0.5);
	$jd=$jd-$UT;
	my $TU=($jd-2451545.0)/36525;
	my $GMST=24110.54841+$TU*(8640184.812866+$TU*(0.093104-$TU*6.2e-6));
	my $thetag_jd=mod2p(2*$pi*($GMST/$secday+$omega_E*$UT));
	return $thetag_jd;
}

sub reduce_angle_to_360
{
	my $angle = shift;

	$angle=$angle-int($angle/360)*360;
	$angle=$angle+360 if( $angle < 0 );		
	return $angle;
}
sub mod2p
{
	my $twopi=$pi*2;
	my $angle = shift;

	$angle=$angle-int($angle/$twopi)*$twopi;
	$angle=$angle+$twopi if( $angle < 0 );		
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
	
	my $julianday=Julian_Day($year,$month,$day);
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
sub get_satellite_pos
{
#
# This code was translated more-or-less directly from the Pascal
# routines contained in a report compiled by TS Kelso and based on:
# Spacetrack Report No. 3
# "Models for Propagation of NORAD Element Sets"
# Felix R. Hoots, Ronald L Roehrich
# December 1980
#
# See TS Kelso's web site for more details...
# Only the SGP propagation model is implemented. 
#
# Steve Franke, K9AN.   9 Dec 1999.

#
#NOAA 15
#1 25338U 98030A   99341.00000000 +.00000376 +00000-0 +18612-3 0 05978
#2 25338 098.6601 008.2003 0011401 112.4684 042.5140 14.23047277081382          
#TDRS 5
#1 21639U 91054B   99341.34471854  .00000095  00000-0  10000-3 0  4928
#2 21639   1.5957  88.4884 0003028 161.6582 135.4323  1.00277774 30562
#OSCAR 16 (PACSAT)
#1 20439U 90005D   99341.14501399 +.00000343 +00000-0 +14841-3 0 02859
#2 20439 098.4690 055.0032 0012163 066.4615 293.7842 14.30320285515297      
#
#Temporary keps database...
#
	my $jtime = shift;
	my $lat = shift;
	my $lon = shift;
	my $alt = shift;
	my $satname = shift;
	my $sat_ref = $keps{$satname};
#printf("$jtime $lat $lon $alt Satellite name = $satname\n");	

	my $qo=120;
	my $so=78;
	my $xj2=1.082616e-3;
	my $xj3=-.253881e-5;
	my $xj4=-1.65597e-6;
	my $xke=.743669161e-1;
	my $xkmper=6378.135;
	my $xmnpda=1440.;
	my $ae=1.;
	my $ck2=.5*$xj2*$ae**2;
	my $ck4=-.375*$xj4*$ae**4;
	my $qoms2t=(($qo-$so)*$ae/$xkmper)**4;
	my $s=$ae*(1+$so/$xkmper);

	my $epoch = $sat_ref ->{epoch};
#printf("epoch = %10.2f\n",$epoch);
	my $epoch_year=int($epoch/1000);
	my $epoch_day=$epoch-int(1000*$epoch_year);
#printf("epoch_year = %10.2f\n",$epoch_year);
#printf("epoch_day = %17.12f\n",$epoch_day);
	my $ep_year=$epoch_year+2000 if ($epoch_year < 57);
	$ep_year=$epoch_year+1900 if ($epoch_year >= 57);
	my $jt_epoch=Julian_Date_of_Year($ep_year);
	$jt_epoch=$jt_epoch+$epoch_day;
#printf("JT for epoch = %17.12f\n",$jt_epoch);
	my $tsince=($jtime-$jt_epoch)*24*60;
#printf("tsince (min) = %17.12f\n",$tsince);

	my $mm1 = $sat_ref ->{mm1};
	my $mm2 = $sat_ref ->{mm2};
	my $bstar=$sat_ref ->{bstar};             # drag term for sgp4 model 
	my $inclination=$sat_ref->{inclination};  # inclination in degrees
	my $raan=$sat_ref->{raan};                # right ascension of ascending node in degs
	my $eccentricity=$sat_ref ->{eccentricity};  # eccentricity - dimensionless
	my $omegao=$sat_ref ->{argperigee};          # argument of perigee in degs
	my $xmo=$sat_ref ->{meananomaly};            # mean anomaly in degrees
	my $xno=$sat_ref ->{meanmotion};             # mean motion in revs per day

#printf("%10.6f %10.6f %10.6f %10.6f %10.6f %10.6f %10.6f %10.6f %10.6f\n",
#$mm1,$mm2,$bstar,$inclination,$raan,$eccentricity,$omegao,$xmo,$xno);
	$raan=$raan*$d2r;
	$omegao=$omegao*$d2r;
	$xmo=$xmo*$d2r;
	$inclination=$inclination*$d2r;
	my $temp=2*$pi/$xmnpda/$xmnpda;
	$xno=$xno*$temp*$xmnpda;
	$mm1=$mm1*$temp;
	$mm2=$mm2*$temp/$xmnpda;

	my $c1=$ck2*1.5;
	my $c2=$ck2/4.0;
	my $c3=$ck2/2.0;
	my $c4=$xj3*$ae**3/(4*$ck2);
	my $cosio=cos($inclination);
	my $sinio=sin($inclination);
	my $a1=($xke/$xno)**(2./3.);
	my $d1=$c1/$a1/$a1*(3*$cosio*$cosio-1)/(1-$eccentricity*$eccentricity)**1.5;
	my $ao=$a1*(1-1./3.*$d1-$d1*$d1-134./81.*$d1*$d1*$d1);
	my $po=$ao*(1-$eccentricity*$eccentricity);
	$qo=$ao*(1-$eccentricity);
	my $xlo=$xmo+$omegao+$raan;
	my $d10=$c3*$sinio*$sinio;
	my $d20=$c2*(7.*$cosio*$cosio-1);
	my $d30=$c1*$cosio;
	my $d40=$d30*$sinio;
	my $po2no=$xno/($po*$po);
	my $omgdt=$c1*$po2no*(5.*$cosio*$cosio-1);
	my $xnodot=-2.*$d30*$po2no;
	my $c5=0.5*$c4*$sinio*(3+5*$cosio)/(1+$cosio);
	my $c6=$c4*$sinio;
	
	my $a=$xno+(2*$mm1+3*$mm2*$tsince)*$tsince;
	$a=$ao*($xno/$a)**(2./3.);
	my $e=1e-6;
	$e =1-$qo/$a if ($a > $qo);
	my $p=$a*(1-$e*$e);
	my $xnodes=$raan+$xnodot*$tsince;
	my $omgas=$omegao+$omgdt*$tsince;
	my $xls=mod2p($xlo+($xno+$omgdt+$xnodot+($mm1+$mm2*$tsince)*$tsince)*$tsince);

	my $axnsl=$e*cos($omgas);
	my $aynsl=$e*sin($omgas)-$c6/$p;
	my $xl=mod2p($xls-$c5/$p*$axnsl);

	my $u=mod2p($xl-$xnodes);
	my $item3;
	my $eo1=$u;
	my $tem5=1;
	my $coseo1=0;
	my $sineo1=0;
	for ($item3=0; abs($tem5) >= 1e-6 && $item3 < 10; $item3++ )
	{
		$sineo1=sin($eo1);
		$coseo1=cos($eo1);
		$tem5=1-$coseo1*$axnsl-$sineo1*$aynsl;
		$tem5=($u-$aynsl*$coseo1+$axnsl*$sineo1-$eo1)/$tem5;
		my $tem2=abs($tem5);
		$tem5=$tem2/$tem5 if ($tem2 > 1);
		$eo1=$eo1+$tem5;
	}

	$sineo1=sin($eo1);
	$coseo1=cos($eo1);
	my $ecose=$axnsl*$coseo1+$aynsl*$sineo1;
	my $esine=$axnsl*$sineo1-$aynsl*$coseo1;
	my $el2=$axnsl*$axnsl+$aynsl*$aynsl;
	my $pl=$a*(1-$el2);
	my $pl2=$pl*$pl;
	my $r=$a*(1-$ecose);
	my $rdot=$xke*sqrt($a)/$r*$esine;
	my $rvdot=$xke*sqrt($pl)/$r;
	$temp=$esine/(1+sqrt(1-$el2));
	my $sinu=$a/$r*($sineo1-$aynsl-$axnsl*$temp);
	my $cosu=$a/$r*($coseo1-$axnsl+$aynsl*$temp);
	my $su=atan2($sinu,$cosu);

	my $sin2u=($cosu+$cosu)*$sinu;
	my $cos2u=1-2*$sinu*$sinu;
	my $rk=$r+$d10/$pl*$cos2u;
	my $uk=$su-$d20/$pl2*$sin2u;
	my $xnodek=$xnodes+$d30*$sin2u/$pl2;
	my $xinck=$inclination+$d40/$pl2*$cos2u;

	my $sinuk=sin($uk);
	my $cosuk=cos($uk);
	my $sinnok=sin($xnodek);
	my $cosnok=cos($xnodek);
	my $sinik=sin($xinck);
	my $cosik=cos($xinck);
	my $xmx=-$sinnok*$cosik;
	my $xmy=$cosnok*$cosik;
	my $ux=$xmx*$sinuk+$cosnok*$cosuk;
	my $uy=$xmy*$sinuk+$sinnok*$cosuk;
	my $uz=$sinik*$sinuk;
	my $vx=$xmx*$cosuk-$cosnok*$sinuk;
	my $vy=$xmy*$cosuk-$sinnok*$sinuk;
	my $vz=$sinik*$cosuk;

	my $x=$rk*$ux*$xkmper/$ae;
	my $y=$rk*$uy*$xkmper/$ae;
	my $z=$rk*$uz*$xkmper/$ae;
	my $xdot=$rdot*$ux;
	my $ydot=$rdot*$uy;
	my $zdot=$rdot*$uz;
	$xdot=($rvdot*$vx+$xdot)*$xkmper/$ae*$xmnpda/86400;
	$ydot=($rvdot*$vy+$ydot)*$xkmper/$ae*$xmnpda/86400;
	$zdot=($rvdot*$vz+$zdot)*$xkmper/$ae*$xmnpda/86400;
#printf("x=%17.6f y=%17.6f z=%17.6f \n",$x,$y,$z);
#printf("xdot=%17.6f ydot=%17.6f zdot=%17.6f \n",$xdot,$ydot,$zdot);
	my ($sat_lat,$sat_lon,$sat_alt,$sat_theta)=Calculate_LatLonAlt($x,$y,$z,$jtime);
	my ($az, $el, $distance) = Calculate_Obs($x,$y,$z,$sat_theta,$xdot,$ydot,$zdot,$jtime,$lat,$lon,$alt);
	return ($sat_lat,$sat_lon,$sat_alt,$az,$el,$distance);
}

sub Calculate_LatLonAlt
{
#
# convert from ECI coordinates to latitude, longitude and altitude.
#
	my $x=shift;
	my $y=shift;
	my $z=shift;
	my $time=shift;

	my $theta=atan2($y,$x);
	my $lon=mod2p($theta-ThetaG_JD($time));
	my $range=sqrt($x**2+$y**2);
	my $f=1/298.26;      # earth flattening constant
	my $e2=$f*(2-$f);
	my $xkmper=6378.135;
	my $lat=atan2($z,$range);
	my ($phi,$c);
	do
	{
		$phi=$lat;
		$c=1/sqrt(1-$e2*sin($phi)**2);
		$lat=atan2($z+$xkmper*$c*$e2*sin($phi),$range);
	} until abs($lat-$phi) < 1e-10;
	my $alt=$range/cos($lat)-$xkmper*$c;
	return ($lat,$lon,$alt,$theta); # radians and kilometers
	
}			

sub Calculate_User_PosVel
{
# change from lat/lon/alt/time coordinates to earth centered inertial (ECI)
# position and local hour angle.
	my $lat=shift;
	my $lon=shift;
	my $alt=shift;
	my $time=shift;
	my $theta=mod2p(ThetaG_JD($time)+$lon);
	my $omega_E=1.00273790934; # earth rotations per sidereal day
	my $secday=86400;
	my $mfactor=2*$pi*$omega_E/$secday;
	my $f=1/298.26;      # earth flattening constant
	my $xkmper=6378.135;
	my $c=1/sqrt(1+$f*($f-2)*sin($lat)**2);
	my $s=(1-$f)*(1-$f)*$c;
	my $achcp=($xkmper*$c+$alt)*cos($lat);
	my $x_user=$achcp*cos($theta);
	my $y_user=$achcp*sin($theta);
	my $z_user=($xkmper*$s+$alt)*sin($lat);
	my $xdot_user=-$mfactor*$y_user;
	my $ydot_user=$mfactor*$x_user;
	my $zdot_user=0;
	return ($x_user,$y_user,$z_user,$xdot_user,$ydot_user,$zdot_user,$theta);
}
sub Calculate_Obs
{
# calculate the azimuth/el of an object as viewed from observers position
# with object position given in ECI coordinates and observer in lat/long/alt.
#
# inputs:	object ECI position vector (km)
#		object velocity vector (km/s)
#		julian time
#		observer lat,lon,altitude (km)
	my $x=shift;
	my $y=shift;
	my $z=shift;
	my $theta_s=shift;
	my $xdot=shift; 
	my $ydot=shift; 
	my $zdot=shift; 
	my $time=shift;
	my $lat=shift;
	my $lon=shift;
	my $alt=shift;

	my ($x_o,$y_o,$z_o,$xdot_o,$ydot_o,$zdot_o,$theta)=
		Calculate_User_PosVel($lat,$lon,$alt,$time);
	my $xx=$x-$x_o;
	my $yy=$y-$y_o;
	my $zz=$z-$z_o;
	my $xxdot=$xdot-$xdot_o;
	my $yydot=$ydot-$ydot_o;
	my $zzdot=$zdot-$zdot_o;

	my $sin_lat=sin($lat);
	my $cos_lat=cos($lat);
	my $sin_theta=sin($theta);
	my $cos_theta=cos($theta);
	
	my $top_s=$sin_lat*$cos_theta*$xx
		+ $sin_lat*$sin_theta*$yy
		- $cos_lat*$zz;

	my $top_e=-$sin_theta*$xx
		+ $cos_theta*$yy;

	my $top_z=$cos_lat*$cos_theta*$xx
		+ $cos_lat*$sin_theta*$yy
		+ $sin_lat*$zz;

	my $az=atan(-$top_e/$top_s);
	$az=$az+$pi if ( $top_s > 0 );
	$az=$az+2*$pi if ( $az < 0 );

	my $range=sqrt($xx*$xx+$yy*$yy+$zz*$zz);
	my $el=asin($top_z/$range);
	return ($az, $el, $range);
}

sub Calendar_date_and_time_from_JD
{
	my ($jd,$z,$frac,$alpha,$a,$b,$c,$d,$e,$dom,$yr,$mon,$day,$hr,$min);
	$jd=shift;
	$jd=$jd+0.5;
	$z=int($jd);
	$frac=$jd-$z;
	$alpha = int( ($z-1867216.5)/36524.25 );
	$a=$z + 1 + $alpha - int($alpha/4);
	$a=$z if( $z < 2299161 );
	$b=$a+1524;
	$c=int(($b-122.1)/365.25);
	$d=int(365.25*$c);
	$e=int(($b-$d)/30.6001);
	$dom=$b-$d-int(30.6001*$e)+$frac;
	$day=int($dom);
	$mon=$e-1 if( $e < 14 );
	$mon=$e-13 if( $e == 14 || $e == 15 );
	$yr = $c-4716 if( $mon > 2 );
	$yr = $c-4715 if( $mon == 1 || $mon == 2 );
	$hr = int($frac*24);
	$min= int(($frac*24 - $hr)*60+0.5);
	if ($min == 60) {   # this may well prove inadequate DJK
		$hr += 1;
		$min = 0;
	}
	return ($yr,$mon,$day,$hr,$min);
}
	


