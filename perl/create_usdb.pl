#!/usr/bin/perl
#
# create a USDB file from a standard raw file (which is GZIPPED BTW)
#
# This will overwrite and remove any existing usdb file, but it will 
# copy the old one first and update that.
#

use strict;

# make sure that modules are searched in the order local then perl
BEGIN {
	# root of directory tree for this system
	use vars qw($root);
	
	$root = "/spider"; 
	$root = $ENV{'DXSPIDER_ROOT'} if $ENV{'DXSPIDER_ROOT'};

	unshift @INC, "$root/perl";	# this IS the right way round!
	unshift @INC, "$root/local";
}

use DXVars;
use USDB;

die "no input (usdbraw?) files specified\n" unless @ARGV;

print "\n", USDB::load(@ARGV), "\n";
exit(0);


