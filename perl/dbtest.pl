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


while (@ARGV) {
	my $fn = shift;
	print "Processing $fn ";
	my $dx = ARRL::DX->new(file=>$fn);
	my $c = $dx->process;
	print "$c paragraphs\n";
}

ARRL::DX::close();

exit 0;
