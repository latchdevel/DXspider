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

	unshift @INC, "$root/local";
}

use vars qw($VERSION $BRANCH);
$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /\d+\.\d+\.(\d+)\.(\d+)/  || (0,0));
$main::build += $VERSION;
$main::branch += $BRANCH;

use DXVars;
use USDB;

die "no input (usdbraw?) files specified\n" unless @ARGV;

USDB::load(@ARGV);
exit(0);


