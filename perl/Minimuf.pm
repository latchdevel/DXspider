#!/usr/bin/perl -w
# A perl Minimuf calculator, nicked from the minimuf program written in
# C.
#
# Translated and modified for my own purposes by Dirk Koopman G1TLH
#
# as fixed by Steve Franke K9AN
#
# Copyright (c) 1999 Dirk Koopman G1TLH
#
# The original copyright:-
#/***********************************************************************
# *                                                                     *
# * Copyright (c) David L. Mills 1994-1998                              *
# *                                                                     *
# * Permission to use, copy, modify, and distribute this software and   *
# * its documentation for any purpose and without fee is hereby         *
# * granted, provided that the above copyright notice appears in all    *
# * copies and that both the copyright notice and this permission       *
# * notice appear in supporting documentation, and that the name        *
# * University of Delaware not be used in advertising or publicity      *
# * pertaining to distribution of the software without specific,        *
# * written prior permission.  The University of Delaware makes no      *
# * representations about the suitability this software for any         *
# * purpose. It is provided "as is" without express or implied          *
# * warranty.                                                           *
# *                                                                     *
# ***********************************************************************
#
# MINIMUF 3.5 from QST December 1982
# (originally in BASIC)
#
# $Id$
#
#

package Minimuf;

use POSIX;

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw($pi $d2r $r2d $halfpi $pi2 $VOFL $R $hE $hF $GAMMA $LN10
		    $MINBETA $BOLTZ $NTEMP $DELTAF $MPATH $GLOSS $SLOSS
            $noise);

use strict;

use vars qw($VERSION $BRANCH);
$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /\d+\.\d+\.(\d+)\.(\d+)/  || (0,0));
$main::build += $VERSION;
$main::branch += $BRANCH;

use vars qw($pi $d2r $r2d $halfpi $pi2 $VOFL $R $hE $hF $GAMMA $LN10
		    $MINBETA $BOLTZ $NTEMP $DELTAF $MPATH $GLOSS $SLOSS
            $noise);
 
$pi = 3.141592653589;
$d2r = ($pi/180);
$r2d = (180/$pi);
$halfpi = $pi/2;
$pi2 = $pi*2;
$VOFL = 2.9979250e8;			# velocity of light
$R = 6371.2;					# radius of the Earth (km)  
$hE = 110;						# mean height of E layer (km) 
$hF = 320;						# mean height of F layer (km) 
$GAMMA = 1.42;					# geomagnetic constant 
$LN10 = 2.302585;				# natural logarithm of 10 
$MINBETA = (10 * $d2r);			# min elevation angle (rad) 
$BOLTZ = 1.380622e-23;			# Boltzmann's constant 
$NTEMP = 290;					# receiver noise temperature (K) 
$DELTAF = 2500;					# communication bandwidth (Hz) 
$MPATH = 3;						# multipath threshold (dB) 
$GLOSS = 3;						# ground-reflection loss (dB) 
$SLOSS = 10;					# excess system loss 
$noise = 10 * log10($BOLTZ * $NTEMP * $DELTAF) + 30;

# basic SGN function
sub SGN
{
	my $x = shift;
	return 0 if $x == 0;
	return ($x > 0) ? 1 : -1;
}

#
# MINIMUF 3.5 (From QST December 1982, originally in BASIC)
#

sub minimuf
{
	my $flux = shift;		# 10-cm solar flux 
	my $month = shift;		# month of year (1 - 12) 
	my $day = shift;		# day of month (1 - 31) 
	my $hour = shift;		# hour of day (utc) (0 - 23) 
	my $lat1 = shift;		# transmitter latitude (deg n) 
	my $lon1 = shift;		# transmitter longitude (deg w) 
	my $lat2 = shift;		# receiver latitude (deg n) 
	my $lon2 = shift;		# receiver longitude (deg w) 
	
	my $ssn;		# sunspot number dervived from flux 
	my $muf;		# maximum usable frequency 
	my $dist;		# path angle (rad) 
	my ($a, $p, $q);		# unfathomable local variables 
	my ($y1, $y2, $y3);
	my ($t, $t4, $t9);
	my ($g0, $g8);
	my ($k1, $k6, $k8, $k9);
	my ($m9, $c0);
	my ($ftemp, $gtemp);	# volatile temps 
	
	# Determine geometry and invariant coefficients
	$ssn = spots($flux);
	$ftemp = sin($lat1) * sin($lat2) + cos($lat1) * cos($lat2) *
	    cos($lon2 - $lon1);
	$ftemp = -1 if ($ftemp < -1);
	$ftemp = 1 if ($ftemp > 1);
	$dist = acos($ftemp);
	$k6 = 1.59 * $dist;
	$k6 = 1 if ($k6 < 1);
	$p = sin($lat2);
	$q = cos($lat2);
	$a = (sin($lat1) - $p * cos($dist)) / ($q * sin($dist));
	$y1 = 0.0172 * (10 + ($month - 1) * 30.4 + $day);
	$y2 = 0.409 * cos($y1);
	$ftemp = 2.5 * $dist / $k6;
	$ftemp = $halfpi if ($ftemp > $halfpi);
	$ftemp = sin($ftemp);
	$m9 = 1 + 2.5 * $ftemp * sqrt($ftemp);
	$muf = 100;

	# Loop along path
	for ($k1 = 1 / (2 * $k6); $k1 <= 1 - 1 / (2 * $k6); $k1 += abs(0.9999 - 1 / $k6)) {
		$gtemp = $dist * $k1;
		$ftemp = $p * cos($gtemp) + $q * sin($gtemp) * $a;
		$ftemp = -1 if ($ftemp < -1);
		$ftemp = 1 if ($ftemp > 1);
		$y3 = $halfpi - acos($ftemp);
		$ftemp = (cos($gtemp) - $ftemp * $p) / ($q * sqrt(1 - $ftemp * $ftemp));
		$ftemp = -1 if ($ftemp < -1);
		$ftemp = 1 if ($ftemp > 1);
		$ftemp = $lon2 + SGN(sin($lon1 - $lon2)) * acos($ftemp);
		$ftemp += $pi2 if ($ftemp < 0);
		$ftemp -= $pi2 if ($ftemp >= $pi2);
		$ftemp = 3.82 * $ftemp + 12 + 0.13 * (sin($y1) + 1.2 * sin(2 * $y1));
		$k8 = $ftemp - 12 * (1 + SGN($ftemp - 24)) * SGN(abs($ftemp - 24));
		if (cos($y3 + $y2) <= -0.26) {
			$k9 = 0;
			$g0 = 0;
		} else {
			$ftemp = (-0.26 + sin($y2) * sin($y3)) / (cos($y2) * cos($y3) + 0.001);
			$k9 = 12 - atan($ftemp / sqrt(abs(1 - $ftemp * $ftemp))) * 7.639437;
			$t = $k8 - $k9 / 2 + 12 * (1 - SGN($k8 - $k9 / 2)) * SGN(abs($k8 - $k9 / 2));
			$t4 = $k8 + $k9 / 2 - 12 * (1 + SGN($k8 + $k9 / 2 - 24)) * SGN(abs($k8 + $k9 / 2 - 24));
			$c0 = abs(cos($y3 + $y2));
			$t9 = 9.7 * pow($c0, 9.6);
			$t9 = 0.1 if ($t9 < 0.1);
			
			$g8 = $pi * $t9 / $k9;
			if (($t4 < $t && ($hour - $t4) * ($t - $hour) > 0.) || ($t4 >= $t && ($hour - $t) * ($t4 - $hour) <= 0)) {
				$ftemp = $hour + 12 * (1 + SGN($t4 - $hour)) * SGN(abs($t4 - $hour));
				$ftemp = ($t4 - $ftemp) / 2;
				$g0 = $c0 * ($g8 * (exp(-$k9 / $t9) + 1)) * exp($ftemp) / (1 + $g8 * $g8);
			} else {
				$ftemp = $hour + 12 * (1 + SGN($t - $hour)) * SGN(abs($t - $hour));
				$gtemp = $pi * ($ftemp - $t) / $k9;
				$ftemp = ($t - $ftemp) / $t9;
				$g0 = $c0 * (sin($gtemp) + $g8 * (exp($ftemp) - cos($gtemp))) / (1 + $g8 * $g8);
				$ftemp = $c0 * ($g8 * (exp(-$k9 / $t9) + 1)) * exp(($k9 - 24) / 2) / (1 + $g8 * $g8);
				$g0 = $ftemp if ($g0 < $ftemp);
			}
		}
		$ftemp = (1 + $ssn / 250) * $m9 * sqrt(6 + 58 * sqrt($g0));
		$ftemp *= 1 - 0.1 * exp(($k9 - 24) / 3);
		$ftemp *= 1 + 0.1 * (1 - SGN($lat1) * SGN($lat2));
		$ftemp *= 1 - 0.1 * (1 + SGN(abs(sin($y3)) - cos($y3)));
		$muf = $ftemp if ($ftemp < $muf);
	}
	return $muf;
}

#
# spots(flux) - Routine to map solar flux to sunspot number.
#
# THis routine was done by eyeball and graph on p. 22-6 of the 1991
# ARRL Handbook. The nice curve fitting was done using Mathematica.
# 
sub spots
{
	my $flux = shift; # 10-cm solar flux 
	my $ftemp;			# double temp 

	return 0 if ($flux < 65);
	if ($flux < 110) {
		$ftemp = $flux - 200.6;
		$ftemp = 108.36 - .005896 * $ftemp * $ftemp;
	} elsif ($flux < 213) {
		$ftemp = 60 + 1.0680 * ($flux - 110);
	} else {
		$ftemp = $flux - 652.9;
		$ftemp = 384.0 - 0.0011059 * $ftemp * $ftemp;
	}
	return $ftemp;
}

# ion - determine paratmeters for hop h
#
# This routine determines the reflection zones for each hop along the
# path and computes the minimum F-layer MUF, maximum E-layer MUF,
# ionospheric absorption factor and day/night flags for the entire
# path.

sub ion
{
	my $h = shift;				# hop index
	my $d = shift;				# path angle (rad)
	my $fcF = shift;			# F-layer critical frequency 
	my $ssn = shift;            # current sunspot number
	my $lat1 = shift;
	my $lon1 = shift;
	my $b1 = shift;
	my $b2 = shift;
	my $lats = shift;
	my $lons = shift;
	
	# various refs to arrays
    my $daynight = shift;		# ref to daynight array one per hop
	my $mufE = shift;
	my $mufF = shift;
	my $absorp = shift;
	
	my $beta;		# elevation angle (rad) 
	my $psi;		# sun zenith angle (rad) 
	my $dhop;		# hop angle / 2 (rad) 
	my $dist;		# path angle (rad) 
	my $phiF;		# F-layer angle of incidence (rad) 
	my $phiE;		# E-layer angle of incidence (rad) 
	my $fcE;		# E-layer critical frequency (MHz) 
	my $ftemp;		# double temp 
    

	# Determine the path geometry, E-layer angle of incidence and
	# minimum F-layer MUF. The F-layer MUF is determined from the
	# F-layer critical frequency previously calculated by MINIMUF
	# 3.5 and the secant law and so depends only on the F-layer
	# angle of incidence. This is somewhat of a crock; however,
	# doing it with MINIMUF 3.5 on a hop-by-hop basis results in
	# rather serious errors.
	 

	$dhop = $d / ($h * 2);
	$beta = atan((cos($dhop) - $R / ($R + $hF)) / sin($dhop));
	$ftemp = $R * cos($beta) / ($R + $hE);
	$phiE = atan($ftemp / sqrt(1 - $ftemp * $ftemp));
	$ftemp = $R * cos($beta) / ($R + $hF);
	$phiF = atan($ftemp / sqrt(1 - $ftemp * $ftemp));
	$absorp->[$h] = $mufE->[$h] = $daynight->[$h] = 0;
	$mufF->[$h] = $fcF / cos($phiF);;
	for ($dist = $dhop; $dist < $d; $dist += $dhop * 2) {

		# Calculate the E-layer critical frequency and MUF.
		 
		$fcE = 0;
		$psi = zenith($dist, $lat1, $lon1, $b1, $b2, $lats, $lons);
		$ftemp = cos($psi);
		$fcE = .9 * pow((180. + 1.44 * $ssn) * $ftemp, .25) if ($ftemp > 0);
		$fcE = .005 * $ssn if ($fcE < .005 * $ssn);
		$ftemp = $fcE / cos($phiE);
		$mufE->[$h] = $ftemp if ($ftemp > $mufE->[$h]);

		# Calculate ionospheric absorption coefficient and
		# day/night indicators. Note that some hops along a
		# path can be in daytime and others in nighttime.

		$ftemp = $psi;
		if ($ftemp > 100.8 * $d2r) {
			$ftemp = 100.8 * $d2r;
			$daynight->[$h] |= 2;
		} else {
			$daynight->[$h] |= 1;
		}
		$ftemp = cos(90. / 100.8 * $ftemp);
		$ftemp = 0. if ($ftemp < 0.);
		$ftemp = (1. + .0037 * $ssn) * pow($ftemp, 1.3);
		$ftemp = .1 if ($ftemp < .1);
		$absorp->[$h] += $ftemp;
	}
}


#
# pathloss(freq, hop) - Compute receive power for given path.
#
# This routine determines which of the three ray paths determined
# previously are usable. It returns the hop index of the best of these
# or zero if none are found.

sub pathloss
{
	my $hop = shift;			# minimum hops 
	my $freq = shift;			# frequency
    my $txpower = shift || 20;	# transmit power 
    my $rsens = shift || -123;	# receiver sensitivity
    my $antgain = shift || 0;   # antenna gain
		
    my $daynight = shift;		# ref to daynight array one per hop
    my $beta = shift;
	my $path = shift;
	my $mufF = shift;
	my $mufE = shift;
    my $absorp = shift;
    my $dB2 = shift;
			
	my $h;						# hop number 
	my $level;					# max signal (dBm) 
	my $signal;					# receive signal (dBm) 
	my $ftemp;					# double temp 
	my $j;						# index temp 

	#
	# Calculate signal and noise for all hops. The noise level is
	# -140 dBm for a receiver bandwidth of 2500 Hz and noise
	# temperature 290 K. The receiver sensitivity is assumed -123
	# dBm (0.15 V at 50 Ohm for 10 dB S/N). Paths where the signal
	# is less than the noise or when the frequency exceeds the F-
	# layer MUF are considered unusable.
	 
	$level = $noise;
	$j = 0;
	for ($h = $hop; $h < $hop + 3; $h++) {
		$daynight->[$h] &= ~(4 | 8 | 16);
		if ($freq < 0.85 * $mufF->[$h]) {

			# Transmit power (dBm)
			 
			$signal = $txpower + $antgain + 30;

			# Path loss
			 
			$signal -= 32.44 + 20 * log10($path->[$h] * $freq) + $SLOSS;

			# Ionospheric loss
			 
			$ftemp = $R * cos($beta->[$h]) / ($R + $hE);
			$ftemp = atan($ftemp / sqrt(1 - $ftemp * $ftemp));
			$signal -= 677.2 * $absorp->[$h] / cos($ftemp) / (pow(($freq + $GAMMA), 1.98) + 10.2);

			# Ground reflection loss
			 
			$signal -= $h * $GLOSS;
			$dB2->[$h] = $signal;

			# Paths where the signal is greater than the
			# noise, but less than the receiver sensitivity
			# are marked 's'. Paths below the E-layer MUF
			# are marked 'e'. When comparing for maximum
			# signal, The signal for these paths is reduced
			# by 3 dB so they will be used only as a last
			# resort.
			 
			
			$daynight->[$h] |= 4 if ($signal < $rsens);
			if ($freq < $mufE->[$h]) {
				$daynight->[$h] |= 8;
				$signal -= $MPATH;
			}
			if ($signal > $level) {
				$level = $signal;
				$j = $h;
			}
		}
	}

	# We have found the best path. If this path is less than 3 dB
	# above the RMS sum of the other paths, the path is marked 'm'.
	 
	return 0 if ($j == 0);

	$ftemp = 0;
	for ($h = $hop; $h < $hop + 3; $h++) {
		$ftemp += exp(2 / 10 * $dB2->[$h] * $LN10) if ($h != $j);
	}
	$ftemp = 10 / 2 * log10($ftemp);
	$daynight->[$j] |= 16 if ($level < $ftemp + $MPATH);
	
	return $j;
}

# zenith(dist) - Determine sun zenith angle at reflection zone.

sub zenith
{
	my $dist = shift;			# path angle 
	my $txlat = shift;          # tx latitude (rad)
	my $txlong = shift;         # tx longitude (rad)
	my $txbearing = shift;      # tx bearing
	my $pathangle = shift;      # 'b1'
	my $lats = shift;           # subsolar latitude
	my $lons = shift;           # subsolar longitude
				
	my ($latr, $lonr);			# reflection zone coordinates (rad) 
	my $thetar;					# reflection zone angle (rad) 
	my $psi;					# sun zenith angle (rad) 

	# Calculate reflection zone coordinates.
	 
	$latr = acos(cos($dist) * sin($txlat) + sin($dist) * cos($txlat) * cos($txbearing));
	$latr += $pi if ($latr < 0);
	$latr = $halfpi - $latr;
	$lonr = acos((cos($dist) - sin($latr) * sin($txlat)) / (cos($latr) * cos($txlat)));
	$lonr += $pi if ($lonr < 0);
	$lonr = - $lonr if ($pathangle < 0);
	$lonr = $txlong - $lonr;
	$lonr -= $pi2 if ($lonr >= $pi);
	$lonr += $pi2 if ($lonr <= -$pi);
	$thetar = $lons - $lonr;
	$thetar = $pi2 - $thetar if ($thetar > $pi);
	$thetar -= $pi2 if ($thetar < - $pi);
	
	# Calculate sun zenith angle.
	 
	$psi = acos(sin($latr) * sin($lats) + cos($latr) * cos($lats) * cos($thetar));
	$psi += $pi if ($psi < 0);
	return($psi);
}

#  official minimuf version of display		
sub dsx
{
	my $h = shift;
	my $rsens = shift;
	my $dB2 = shift;
	my $daynight = shift;
	
	my $c1;
	my $c2;

	return "       " unless $h;
	
	if (($daynight->[$h] & 3) == 3) {
		$c1 = 'x';
	} elsif ($daynight->[$h] & 1) {
		$c1 = 'j';
	} elsif ($daynight->[$h] & 2) {
		$c1 = 'n';
	}
	if ($daynight->[$h] & 4) {
		$c2 = 's';
	} elsif ($daynight->[$h] & 16) {
		$c2 = 'm';
	} else {
		$c2 = ' ';
	}
    return sprintf("%4.0f%s%1d%s", $dB2->[$h] - $rsens, $c1, $h, $c2)
}		

#  my version
sub ds
{
	my $h = shift;
	my $rsens = shift;
	my $dB2 = shift;
	my $daynight = shift;
	
	my $c2;

	return "    " unless $h;
	
	if ($daynight->[$h] & 4) {
		$c2 = 's';
	} elsif ($daynight->[$h] & 16) {
		$c2 = 'm';
	} else {
		$c2 = ' ';
	}
	my $l = $dB2->[$h] - $rsens;
	my $s = int $l / 6;
	$s = 9 if $s > 9;
	$s = 0 if $s < 0;
    my $plus = (($l / 6) >= $s + 0.5) ? '+' : ' ';
	
    return "$c2". "S$s$plus";
}		

1;
