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

use strict;
use vars qw($pi);

$pi = 3.14159265358979;

# half a qra to lat long translation
sub _half_qratoll
{
	my ($l, $n, $m) = @_;
	my $lat = ord($l) - ord('A');
	$lat = $lat * 10 + (ord($n) - ord('0'));
	$lat = $lat * 24 + (ord($m) - ord('A'));
	$lat -= (2160 + 0.5);
	$lat = $lat * ($pi/4320);
	
} 
# convert a qra locator into lat/long in DEGREES
sub qratoll
{
	my $qra = uc shift;
	my $long = _half_qratoll((unpack 'AAAAAA', $qra)[0,2,4]) * 2;
	my $lat = _half_qratoll((unpack 'AAAAAA', $qra)[1,3,5]);
	return (rd($lat), rd($long));
}

sub _part_lltoqra
{
	my ($t, $f, $n, $e) = @_;
	$n = $f * ($n - int($n));
	$e = $f * ($e - int($e));
	my $q = chr($t+$e) . chr($t+$n);
	return ($q, $n, $e);
}

# convert a lat, long in DEGREES to a qra locator 
sub lltoqra
{
	my $lat = dr(shift);
	my $long = dr(shift);
	my $t = 1/6.283185;

	$long = $long * $t +.5 ;
	$lat = $lat * $t * 2 + .5 ;

	my $q;
	my $qq;
	($q, $lat, $long) = _part_lltoqra(ord('A'), 18, $lat, $long);
	$qq = $q;
	($q, $lat, $long) = _part_lltoqra(ord('0'), 10, $lat, $long);
	$qq .= $q;
	($q, $lat, $long) = _part_lltoqra(ord('A'), 24, $lat, $long);
	$qq .= $q;
	return $qq;
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

# does it look like a qra locator?
sub is_qra
{
	my $qra = shift;
	return $qra =~ /^[A-Za-z][A-Za-z]\d\d[A-Za-z][A-Za-z]$/o;
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
	my ($latd, $latm, $latl, $longd, $longm, $longl) = split /\s+/, shift;
	
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
	my ($latd, $latm, $longd, $longm);
	my $latl = $lat > 0 ? 'N' : 'S';
	my $longl = $long > 0 ? 'E' : 'W';
	
	$lat = abs $lat;
	$latd = int $lat;
	$lat -= $latd;
	$latm = int (60 * $lat);
	
	$long = abs $long;
	$longd = int $long;
	$long -= $longd;
	$longm = int (60 * $long);
	return "$latd $latm $latl $longd $longm $longl";
}
1;
