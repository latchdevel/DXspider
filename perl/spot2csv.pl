#!/usr/bin/env perl
#
# convert a DXSpider Spot file to csv format
#
# usage: spot2csv.pl <filename> ...
#
# Copyright (c) 2001 Dirk Koopman G1TLH
#
#
# 
# make sure that modules are searched in the order local then perl
use strict;

BEGIN {
	# root of directory tree for this system
	use vars qw($root $is_win);
	$root = "/spider"; 
	$root = $ENV{'DXSPIDER_ROOT'} if $ENV{'DXSPIDER_ROOT'};
	
	unshift @INC, "$root/perl";	# this IS the right way round!
	unshift @INC, "$root/local";

	$is_win = ($^O =~ /^MS/ || $^O =~ /^OS-2/) ? 1 : 0; # is it Windows?
}

use DXUtil;

die "usage: spot2csv.pl <filename> ....\n" unless @ARGV;

my $crnl = $is_win ? "\015\012" : "\012";

for (@ARGV) {
	unless (open IN, $_) {
		print STDERR "cannot open $_ $!\n";
		next;
	}
	while (<IN>) {
		chomp;
		s/([\%\"\'\x00-\x1f\x7f-\xff])/sprintf("%%%02X", ord($1))/eg;
		my @spot =  split '\^';
		my $date = unpad cldate($spot[2]);
		my $time = unpad ztime($spot[2], 1);
		print "$spot[0]\t\"$spot[1]\"\t\"$date\"\t$time\t";
		print $spot[3] ? "\"$spot[3]\"\t" : "\t";
		print "\"$spot[4]\"\t$spot[5]\t$spot[6]\t\"$spot[7]\"$crnl";
	}
	close IN;
}




