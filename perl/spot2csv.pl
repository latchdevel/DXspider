#!/usr/bin/perl -w
#
# convert a DXSpider Spot file to csv format
#
# usage: spot2csv.pl <filename> ...
#
# Copyright (c) 2001 Dirk Koopman G1TLH
#
# $Id$
# 

# make sure that modules are searched in the order local then perl
use DXUtil;

use strict;

die "usage: spot2csv.pl <filename> ....\n" unless @ARGV;

for (@ARGV) {
	unless (open IN, $_) {
		print STDERR "cannot open $_ $!\n";
		next;
	}
	while (<IN>) {
		chomp;
		s/([\%\"\'\x00-\x1f\x7f-\xff])/sprintf("%%%02X", ord($1))/eg;
		my @spot =  split '\^';
		my $date = cldate($spot[2]);
		my $time = ztime($spot[2], 1);
		print "$spot[0]\t\"$spot[1]\"\t\"$date\"\t$time\t";
		print $spot[3] ? "\"$spot[3]\"\t" : "\t";
		print "\"$spot[4]\"\t$spot[5]\t$spot[6]\t\"$spot[7]\"\r\n";
	}
	close IN;
}




