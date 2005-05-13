#!/usr/bin/perl
# test for independent sql servers
# search local then perl directories

use vars qw($root);

BEGIN {
	# root of directory tree for this system
	$root = "/spider"; 
	$root = $ENV{'DXSPIDER_ROOT'} if $ENV{'DXSPIDER_ROOT'};
	
	unshift @INC, "$root/perl";	# this IS the right way round!
	unshift @INC, "$root/local";
}

use DXUtil;
use DXDebug;
use ARRL::DX;


my $dx = ARRL::DX->new;

exit 0;
