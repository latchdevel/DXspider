#!/usr/bin/env perl
#
# convert a DXSpider Log file to csv format
#
# usage: log2csv.pl <filename> ...
#
# Copyright (c) 2005 Dirk Koopman G1TLH
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

die "usage: log2csv.pl <filename> ....\n" unless @ARGV;

my $crnl = $is_win ? "\015\012" : "\012";

for (@ARGV) {
	unless (open IN, $_) {
		print STDERR "cannot open $_ $!\n";
		next;
	}
	while (<IN>) {
		chomp;
		s/([\%\"\'\x00-\x1f\x7f-\xff])/sprintf("%%%02X", ord($1))/eg;
		my @line =  split '\^';
		my $date = unpad cldate($line[0]);
		my $time = unpad ztime($line[0], 1);
		print "$date\t$time\t$line[1]";
		shift @line;
	    shift @line;
		while (@line < 3) {
			unshift @line, '';
		}
		print "\t", join("\t", @line), $crnl;
	}
	close IN;
}




