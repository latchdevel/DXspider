#!/usr/bin/perl
#
# Export the user file in a form that can be directly imported
# back with a do statement
#

require 5.004;

# search local then perl directories
BEGIN {
	umask 002;
	
	# root of directory tree for this system
	$root = "/spider"; 
	$root = $ENV{'DXSPIDER_ROOT'} if $ENV{'DXSPIDER_ROOT'};
	
	unshift @INC, "$root/perl";	# this IS the right way round!
	unshift @INC, "$root/local";
}

use DXVars;
use DXUser;
use Carp;

$userfn = $ARGV[0] if @ARGV;
unless ($userfn) {
	croak "need a filename";
}

DXUser->init($userfn, 1);

do "$userfn.asc";
print $@ if $@;

DXUser->finish();
