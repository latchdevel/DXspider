#
# a program to create a prefix file from a wpxloc.raw file
#
# Copyright (c) - Dirk Koopman G1TLH
#
# $Id$
#

use DXVars;

# open the input file
$ifn = $ARGV[0] if $ARGV[0];
$ifn = "$data/wpxloc.raw" if !$fn;
open (IN, $ifn) or die "can't open $ifn ($!)";

while (<IN>) {
  next if /^\!/;    # ignore comment lines
  chomp;
  @f = split;       # get each 'word'
  @pre = split /\,/, $f[0];    # split the callsigns
}
