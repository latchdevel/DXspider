#!/usr/bin/perl
#
# convert an Ak1a DX.DAT file to comma delimited form
#
#

use Date::Parse;
use Spot;
use Prefix;

sysopen(IN, "../data/DX.DAT", 0) or die "can't open DX.DAT ($!)";
open(OUT, ">../data/dxcomma") or die "can't open dxcomma ($!)";

Prefix::load();

$fn = Spot::prefix();
system("rm -rf $fn/*");

while (sysread(IN, $buf, 86)) {
  ($freq,$call,$date,$time,$comment,$spotter) = unpack 'A10A13A12A6A31A14', $buf;
  $d = $date =~ s/^\s*(\d+)-(\w\w\w)-(19\d\d)$/$1 $2 $3/o;
  $t = $time =~ s/^(\d\d)(\d\d)Z$/$1:$2 +0000/o;
  $dt = undef;
  $dt = str2time("$date $time") if $d && $t;
  $comment =~ s/^\s+//o;
  if ($dt ) {
    Spot::add($freq, $call, $dt, $comment, $spotter);
  } else {
    print "$call $freq $date $time\n";
  }
}

close(IN);
close(OUT);
