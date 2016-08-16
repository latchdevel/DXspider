#!/usr/bin/env perl
#
# alias testing tool
#

# search local then perl directories
BEGIN {
  # root of directory tree for this system
  $root = "/spider"; 
  $root = $ENV{'DXSPIDER_ROOT'} if $ENV{'DXSPIDER_ROOT'};

  unshift @INC, "$root/perl";   # this IS the right way round!
  unshift @INC, "$root/local";
}

use SysVar;
use CmdAlias;

use Carp;

while (<>) {
  chomp;
  last if /^q$/;
  
  $o1 = CmdAlias::get_cmd($_);
  $o2 = CmdAlias::get_hlp($_);
  print "in: $_ cmd: $o1 hlp: $o2\n";
}
