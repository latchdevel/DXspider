#!/usr/bin/perl
#
# convert an AK1A DX.DAT file to comma delimited form
#
# PLEASE BE WARNED:
#
# This routine is really designed for archive data. It will create and add to 
# standard DXSpider spot files. If those spot files already exist (because you
# were running DXSpider at the same time as collecting this 'old' data) then
# this will simply append the data onto the end of the appropriate spot file
# for that day. This may then give strange 'out of order' results when viewed
# with the show/dx command
#
# $Id$
#
# Copyright (c) 1998-2003 Dirk Koopman G1TLH
#

# search local then perl directories
BEGIN {
	# root of directory tree for this system
	$root = "/spider"; 
	$root = $ENV{'DXSPIDER_ROOT'} if $ENV{'DXSPIDER_ROOT'};
	
	unshift @INC, "$root/perl";	# this IS the right way round!
	unshift @INC, "$root/local";
}

use DXUtil;
use Spot;
use Prefix;

$ifn = "$root/data/DX.DAT";
$ifn = shift if @ARGV;
print "Using: $ifn as input... \n";

sysopen(IN, $ifn, 0) or die "can't open $ifn ($!)";

Prefix::init();
Spot::init();

while (sysread(IN, $buf, 86)) {
  ($freq,$call,$date,$time,$comment,$spotter) = unpack 'A10A13A12A6A31A14', $buf;
#  printf "%-13s %10.1f %s %s by %s %s\n", $call, $freq, $date, $time, $spotter, $comment;
  
  $dt = cltounix($date, $time);
  $comment =~ s/^\s+//o;
  if ($dt ) {
	  my @spot = Spot::prepare($freq, $call, $dt, $comment, $spotter);
	  Spot::add(@spot);
  } else {
    print "ERROR: $call $freq $date $time by $spotter $comment\n";
  }
}

close(IN);
