#!/usr/bin/perl
#
# This example takes METARs from the standard input and 
# prints them out in a readable form
#

use strict;
use Geo::TAF;

while (<STDIN>) {
	chomp;
	next if /^\s*$/;
	next unless Geo::TAF::is_weather($_);
	my $t = new Geo::TAF;
	$t->metar($_);
	print $t->raw, "\n\n";
	print $t->as_string, "\n\n";
}
