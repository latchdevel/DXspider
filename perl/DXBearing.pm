#
# bearing and distance calculations together with
# locator convertions to lat/long and back
#
# some of this is nicked from 'Amateur Radio Software' by 
# John Morris GM4ANB and tranlated into perl from the original
# basic by me - I have factorised it where I can be bothered
#
# Copyright (c) 1998 - Dirk Koopman G1TLH
#
# $Id$
#

package DXBearing;

use POSIX;
use DXUtil;

use strict;
use vars qw($pi);

$pi = 3.14159265358979;

use vars qw($VERSION $BRANCH);
$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /\d+\.\d+\.(\d+)\.(\d+)/,(0,0));
$main::build += $VERSION;
$main::branch += $BRANCH;

# convert a qra locator into lat/long in DEGREES
sub qratoll
{
	my $qra = uc shift;
	my ($p1, $p2, $p3, $p4, $p5, $p6) = unpack 'AAAAAA', $qra;
	($p1, $p2, $p3, $p4, $p5, $p6) = (ord($p1)-ord('A'), ord($p2)-ord('A'), ord($p3)-ord('0'), ord($p4)-ord('0'), ord($p5)-ord('A'), ord($p6)-ord('A') );
	
	my $long = ($p1*20) + ($p3*2) + (($p5+0.5)/12) - 180;
    my $lat = ($p2*10) + $p4 + (($p6+0.5)/24) - 90;
	return ($lat, $long);
}

# convert a lat, long in DEGREES to a qra locator 
sub lltoqra
{
	my $lat = shift;
	my $long = shift;

	my $v;
	my ($p1, $p2, $p3, $p4, $p5, $p6);
	
	$lat += 90;
	$long += 180;
	$v = int($long / 20); 
	$long -= ($v * 20);
	$p1 = chr(ord('A') + $v);
	$v = int($lat / 10);			   
	$lat -= ($v * 10);
	$p2 = chr(ord('A') + $v);
	$p3 = int($long/2);
	$p4 = int($lat);
	$long -= $p3*2;
	$lat -= $p4;
	$p3 = chr(ord('0')+$p3);
	$p4 = chr(ord('0')+$p4);
	$p5 = int((12 * $long) );
	$p6 = int((24 * $lat) );
	$p5 = chr(ord('A')+$p5);
	$p6 = chr(ord('A')+$p6);

	return "$p1$p2$p3$p4$p5$p6";
}

# radians to degrees
sub rd
{
	my $n = shift;
	return ($n / $pi) * 180;
}

# degrees to radians
sub dr 
{
	my $n = shift;
	return ($n / 180) * $pi;
}

# calc bearing and distance, with arguments in DEGREES
# home lat/long -> lat/long
# returns bearing (in DEGREES) & distance in KM
sub bdist
{
	my $hn = dr(shift);
	my $he = dr(shift);
	my $n = dr(shift);
	my $e = dr(shift);
	return (0, 0) if $hn == $n && $he == $e;
	my $co = cos($he-$e)*cos($hn)*cos($n)+sin($hn)*sin($n);
	my $ca = atan(abs(sqrt(1-$co*$co)/$co));
	$ca = $pi-$ca if $co < 0;
	my $dx = 6367*$ca;
	my $si = sin($e-$he)*cos($n)*cos($hn);
	$co = sin($n)-sin($hn)*cos($ca);
	my $az = atan(abs($si/$co));
	$az = $pi - $az if $co < 0;
	$az = -$az if $si < 0;
	$az = $az+2*$pi if $az < 0;
	return (rd($az), $dx);
}

# turn a lat long string into floating point lat and long
sub stoll
{
	my ($latd, $latm, $latl, $longd, $longm, $longl) = $_[0] =~ /(\d{1,2})\s+(\d{1,2})\s*([NnSs])\s+(1?\d{1,2})\s+(\d{1,2})\s*([EeWw])/;
	
	$longd += ($longm/60);
	$longd = 0-$longd if (uc $longl) eq 'W'; 
	$latd += ($latm/60);
	$latd = 0-$latd if (uc $latl) eq 'S';
	return ($latd, $longd);
}

# turn a lat and long into a string
sub lltos
{
	my ($lat, $long) = @_;
	my $slat = slat($lat);
	my $slong = slong($long);
	return "$slat $slong";
}
1;
