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

print "usage:\tdbquery.pl <words>\n\teg: dbquery.pl rtty lebanon\n\n" unless @ARGV;

my $width = $ENV{'COLUMNS'} || $ENV{'COLS'} || 80;
my $dx = ARRL::DX->new();
my @out = $dx->query(q=>join(' ', @ARGV));

foreach my $ref (@out) {
	my $s = cldate($ref->[1]);
	for (split /\s+/, "$ref->[0] [$ref->[2]]") {
		if (length($s) + length($_) + 1 < $width ) {
			$s .= ' ' if length $s;
			$s .= $_;
		} else {
			print "$s\n";
			$s = $_;
		}
	}
	print "$s\n" if length $s;
	print "\n";
}

exit 0;
