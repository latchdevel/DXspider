#!/usr/bin/perl
#
#
use lib qw(.);
use Math::Round qw(:all);
use JSON;
use Text::Morse;

$morse = new Text::Morse;

while (<>) {
	next unless /SK0MMR/;
	($gts,$sk,$f,$c,$md,$str,$zt)=m|^(\d+)\^.*DX de ([-\w\d/]+)-\#:\s+([\.\d]+)\s+([-\w\d/]+)\s+(\w{1,3})\s+(-?\d+).*(\d{4})Z|;
	next unless $sk && $c;
	$e = sprintf "%010d", nearest(5, $f*10);
	$m = ''; #$morse->Encode($c);
	$t10 = nearest(60, $gts);
	$key = "$zt|$e";

    $r = $spot{$key} ||= {};
	$s = $r->{"$c|$m"} ||= {};
	my ($sec,$min,$hour) = gmtime $gts;
	$s->{$sk} = sprintf "%-.3s %4d %.1f %02d:%02d:%02d", $md, $str, $f, $hour, $min, $sec;
	
	++$skim{$sk};
	++$call{$c};
}	

$json = JSON->new->canonical(1)->indent(1);
print $json->encode(\%spot), "\n";
print $json->encode(\%skim), "\n";
print $json->encode(\%call), "\n";

$spotk = keys %spot;
$skimk = keys %skim;
$callk = keys %call;

print "spots: $spotk skimmers: $skimk spotted calls: $callk\n";
