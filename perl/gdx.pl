#!/usr/bin/perl
#
# grep for expressions in various fields of the dx file
#

# search local then perl directories
BEGIN {
	# root of directory tree for this system
	$root = "/spider"; 
	$root = $ENV{'DXSPIDER_ROOT'} if $ENV{'DXSPIDER_ROOT'};
	
	unshift @INC, "$root/perl";	# this IS the right way round!
	unshift @INC, "$root/local";
}

use IO::Handle;
use DXUtil;
use Bands;
use Spot;

$dxdir = "/spider/cmd/show";
$dxcmd = "dx.pl";
$s = readfilestr($dxdir, $dxcmd);
$dxproc = eval "sub { $s }";
die $@ if $@;

STDOUT->autoflush(1);
Spot::init();
Bands::load();

for (;;) {
  print "expr: ";
  $expr = <STDIN>;
  last if $expr =~ /^q/i;

  chomp $expr;

  my @out = map {"$_\n"} &$dxproc({priv=>0,call=>'GDX'}, $expr);
  shift @out;   # remove return code
  print @out;
}

