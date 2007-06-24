#!/usr/bin/perl
# 
# A program to split out the Command_en.hlp file into two
# html documents, one for sysops, one for users
#
# Copyright (c) - 1999 Dirk Koopman G1TLH
#
#
#
require 5.004;

# search local then perl directories
BEGIN {
	# root of directory tree for this system
	$root = "/spider"; 
	$root = $ENV{'DXSPIDER_ROOT'} if $ENV{'DXSPIDER_ROOT'};
	
	unshift @INC, "$root/perl";	# this IS the right way round!
	unshift @INC, "$root/local";
}

use strict;
use IO::File;
use DXVars;
use Carp;

my $lang = 'en';
$lang = shift @ARGV if @ARGV;


# read in the help file and key it all up and store it
my $h = new IO::File;

if (!open($h, "$main::localcmd/Commands_$lang.hlp")) {
	if (!open($h, "$main::cmd/Commands_$lang.hlp")) {
		die "cannot open $main::cmd/Commands_$lang.hlp $!";
	}
}
my $in;
my $state = 0;
my $ref;
my $text;
my %c;

foreach $in (<$h>) {
	chomp;
	next if $in =~ /^\#/;
	$in =~ s/</\&lt;/g;
	$in =~ s/>/\&gt;/g;
	if ($in =~ /^===/) {
		$text = [ ] if $state != 1;   # new text reference if not in a list
		$in =~ s/=== //;
		my ($priv, $cmd, $desc) = split /\^/, $in;
		$c{$cmd} = { cmd=>$cmd, priv=>$priv, desc=>$desc, text=> $text };
		$state = 1;
		next;
	}
	if ($state > 0) {
		confess "no text!" unless $text;
	    push @$text, $in;
		$state = 2;
	}
}

close($h);

# At this point we should have a hash containing all the useful info on each command

# Starting with the user file, open it and copy across the top and tail with the 
# <data> tag replaced by this system.
#

my $html = "$main::root/html";
my $in = new IO::File "$html/user_$lang\_t.html" or die "can't open $html/user_$lang\_t.html $!";
my $out = new IO::File ">$html/user_$lang.html" or die "can't open $html/user_$lang.html $!";
chmod 0664, "$html/user_$lang.html";

# copy until <data> is nigh
while (<$in>) {
	last if /<data>/i;
	print $out $_;
}

my $c;
my $count;
my %done;

foreach $c (sort {$a->{cmd} cmp $b->{cmd}} values %c) {
	next if $c->{priv};
	$count++;
    my $label = "L$count";
	print $out "<li><a name=\"$label\"><b>$c->{cmd}</b></a> $c->{desc}<br><br>\n";
	printlines($out, $c->{text});
}

# now copy the rest out
while (<$in>) {
	print $out $_;
}

$in->close;
$out->close;

exit(0);

sub printlines
{
	my $fh = shift;
	my $ref = shift;

	my $last;
	my $state = 0;
	for (@$ref) {
		if ($state == 0) {
			if (/^\s+\S+/) {
				print $fh "<pre>\n";
				$state = 1;
			}
		} else {
			unless (/^\s+\S+/) {
				print $fh "</pre>\n";
				$state = 0;
			}
		}
		print $fh $_, " ";
    
		if (/^\s*$/) {
            if ($last =~ /^\s*$/) {
				print $fh "<br>\n";
			} else {
				print $fh "<br><br>\n";
			}
		}
		$last = $_;
	}
#    print $fh "<br>\n";
}
