#!/usr/bin/perl
#
# Process and import for mail WWV and Solar Data
#
# This program takes a mail message on its standard input
# and, if it is WWV or Solar info, imports it into the local
# spider chat_import queue.
#
# Both the "tmp" and the "chat_import" directories should be
# chmod 1777 
#
# Copyright (c) 2004 Dirk Koopman G1TLH
#
# $Id$
#

use strict;
use Mail::Internet;
use Mail::Header;

our $root;

# search local then perl directories
BEGIN {
	# root of directory tree for this system
	$root = "/spider"; 
	$root = $ENV{'DXSPIDER_ROOT'} if $ENV{'DXSPIDER_ROOT'};
	
	unshift @INC, "$root/perl";	# this IS the right way round!
	unshift @INC, "$root/local";
}

my $import = "$root/chat_import";
my $tmp = "$root/tmp";

my $msg = Mail::Internet->new(\*STDIN) or die "Mail::Internet $!";
my $head = $msg->head->header_hashref;

if ($head) {
	if ($head->{Subject}->[0] =~ /wwv/i) {
		process_wwv($msg);
	} elsif ($head->{From}->[0] =~ /rwc\.boulder/i || $head->{'From '}->[0] =~ /rwc\.boulder/i) {
		process_solar($msg);
	}
}

exit(0);

sub process_wwv
{
	my $msg = shift;
	my @out;
	my $state;
	
	foreach (@{$msg->body}) {
		next if /^\s*:/;
		next if /^\s#/;
		next if /^\s*\r?\n$/s;
		if (/follow/) {
			$state = 1;
			next;
		}
		if ($state) {
			my $l = $_;
			next if /\bSec\b/i;
			$l =~ s/\s*\.?\r?\n$//;
			push @out, $l;
		}
	}
	out(@out) if @out;
}

sub process_solar
{
	my $msg = shift;
	my @out;
	my $state;
	
	foreach (@{$msg->body}) {
		if (!$state && /Space\s+Weather\s+Message\s+Code:/i) {
			$state = 1;
		}
		if ($state == 1 && /^[A-Z]+:/) {
			$state = 2;
		}
		if ($state == 2 && /^\s*\r?\n$/s) {
			last;
		}
		if ($state > 1) {
			my $l = $_;
			next if /\bSec\b/i;
			$l =~ s/\r?\n$//;
			push @out, $l;
		}
	}
	out(@out) if @out;
}

sub out
{
	my $fn = "solar.txt.$$";
   
	open OUT, ">$tmp/$fn" or die "import $tmp/$fn $!";
	chmod 0666, "$tmp/$fn";
	print OUT map { "$_\n" } @_;
	close OUT;

	# Note we do this this way to make the appearance of
	# the file in /spider/chat_import atomic. Otherwise there
	# exists the possiblity of race conditions and other nasties
	link "$tmp/$fn", "$import/$fn";
	unlink "$tmp/$fn";
}

