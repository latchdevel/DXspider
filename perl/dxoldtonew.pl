#!/usr/bin/perl
#
# convert an Ak1a DX.DAT file to comma delimited form
#
#

use Date::Parse;
use spot;

sysopen(IN, "../data/DX.DAT", 0) or die "can't open DX.DAT ($!)";
open(OUT, ">../data/dxcomma") or die "can't open dxcomma ($!)";

spot->init();

while (sysread(IN, $buf, 86)) {
  ($freq,$call,$date,$time,$comment,$spotter) = unpack 'A10A13A12A6A31A14', $buf;
  $date =~ s/^\s*(\d+)-(\w\w\w)-(19\d\d)$/$1 $2 $3/og;
  $time =~ s/^(\d\d)(\d\d)Z$/$1:$2 +0000/;
  $d = str2time("$date $time");
  $comment =~ s/^\s+//o;
  if ($d) {
    spot->new($freq, $call, $d, $comment, $spotter);
  } else {
    print "$call $freq $date $time\n";
  }
}

close(IN);
close(OUT);
