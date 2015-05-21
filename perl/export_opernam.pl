#!/usr/bin/env perl
#
# export a standard ak1a opernam.dat file into CSV format.
#
# Copyright (c) 1999 Dirk Koopman G1TLH
#
#

sub export
{
	my $rec = shift;
	my @f = unpack "SA13A23SA12A6SSSSA1CSSSA1A80A1A13A1", $rec;
	my $f;

	# clean each field
	for $f (@f) {
		my @a = split m{\0}, $f;
		$f = $a[0] if @a > 1;
	}

	print join '|', @f;
	print "\n";
}

die "Need an filename" unless @ARGV;
open IN, $ARGV[0] or die "can't open $ARGV[0] ($!)";

while (sysread(IN, $buf, 196)) {
	export($buf);
}
close IN;
exit(0);
