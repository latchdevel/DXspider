#!/usr/bin/perl
#
# Process and import for mail SIDC Ursagrams
#
# This program takes a mail message on its standard input
# and, if it is an URSIGRAM, imports it into the local
# spider msg queue.
#
# Copyright (c) Dirk Koopman G1TLH
#
# $Id$
#

use strict;
use Mail::Internet;
use Mail::Header;

my $import = '/spider/msg/import';

my $msg = Mail::Internet->new(\*STDIN) or die "Mail::Internet $!";
my $head = $msg->head->header_hashref;

if ($head && $head->{From}->[0] =~ /sidc/i && $head->{Subject}->[0] =~ /Ursigram/i) {
	my $body = $msg->body;
	my $title = 'SIDC Ursigram';
	my $date = '';
	foreach my $l (@$body) {
		if ($l =~ /SIDC\s+SOLAR\s+BULLETIN\s+(\d+)\s+(\w+)\s+20(\d\d)/) {
			$date = "$1$2$3";
			$title .= " $date";
			last;
		}
	}
	open OUT, ">$import/ursigram$date.txt" or die "import $!";
	print OUT "SB ALL\n$title\n";
	print OUT map {s/\r\n$/\n/; $_} @$body;
	print OUT "/ex\n";
	close OUT;
}

exit(0);
