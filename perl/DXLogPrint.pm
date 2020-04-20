#
# Log Printing routines
#
# Copyright (c) - 1998 Dirk Koopman G1TLH
#
#
#

package DXLog;

use 5.10.1;

use IO::File;
use DXVars;
use DXDebug qw(dbg isdbg);
use DXUtil;
use DXLog;
use Julian;


our $readback = `which tac`;
chomp $readback;

use strict;

use vars qw($maxmonths);
$maxmonths = 36;

#
# print some items from the log backwards in time
#
# This command outputs a list of n lines starting from time t with $pattern tags
#
sub print
{
	my $fcb = $DXLog::log;
	my $from = shift || 0;
	my $to = shift || 10;
	my $jdate = $fcb->unixtoj(shift);
	my $pattern = shift;
	my $who = shift;
	my $search;
	my @in;
	my @out = ();
	my $eval;
	my $tot = $from + $to;
	my $hint = "";
	    
	$who = uc $who if defined $who;

	if ($pattern) {
		$hint = q{m{\Q$pattern\E}i};
	} else {
		$hint = q{!m{\^(?:ann|rcmd|talk|chat)\^}};
	}
	if ($who) {
		$hint .= ' && ' if $hint;
		$hint .= q{m{\Q$who\E}oi};
	} 
	$hint = "next unless $hint" if $hint;
	$hint .= "; next unless m{^\\d+\\^$pattern\\^}" if $pattern;
	$hint ||= "";
	
	$eval = qq(while (<\$fh>) {
				   $hint;
				   chomp;
                   # say "line: \$_";
				   push \@in, \$_;
                   last L1 if \@in >= $tot;
			   } );
	
	if (isdbg('search')) {
		dbg("sh/log hint: $hint");
		dbg("sh/log eval: $eval");
	}
	
	$fcb->close;                                      # close any open files

	my $months;
	my $fh;
	if ($readback) {
		my $fn = $fcb->fn($jdate);
		$fh = IO::File->new("$readback $fn |");
	} else {
		$fh = $fcb->open($jdate); 	
	}
 L1: for ($months = 0; $fh && $months < $maxmonths && @in < $tot; $months++) {
		my $ref;

		if ($fh) {
			my @tmp;
			eval $eval;               # do the search on this file
			return ("Log search error", $@) if $@;
		}

		if ($readback) {
			my $fn = $fcb->fn($jdate->sub(1));
			$fh = IO::File->new("$readback $fn |");
		} else {
			$fh = $fcb->openprev();      # get the next file
		}
	}

	unless (@in) {
		my $name = $pattern ? $pattern : "log";
		my $s = "$who "|| '';
		return "show/$name: ${s}not found";
	} 

	for (reverse @in) {
		my @line = split /\^/ ;
		push @out, print_item(\@line);
	
	}
	return @out;
}


#
# the standard log printing interpreting routine.
#
# every line that is printed should call this routine to be actually visualised
#
# Don't really know whether this is the correct place to put this stuff, but where
# else is correct?
#
# I get a reference to an array of items
#
sub print_item
{
	my $r = shift;
	my $d = atime($r->[0]);
	my $s = 'undef';
	
	if ($r->[1] eq 'rcmd') {
		$r->[6] ||= 'Unknown';
		if ($r->[2] eq 'in') {
			$r->[5] ||= "";
			$s = "in: $r->[4] ($r->[6] priv: $r->[3]) rcmd: $r->[5]";
		} else {
			$r->[4] ||= "";
			$s = "$r->[3] $r->[6] reply: $r->[4]";
		}
	} elsif ($r->[1] eq 'talk') {
		$r->[5] ||= "";
		$s = "$r->[3] -> $r->[2] ($r->[4]) $r->[5]";
	} elsif ($r->[1] eq 'ann' || $r->[1] eq 'chat') {
		$r->[4] ||= "";
		$r->[4] =~ s/^\#\d+ //;
		$s = "$r->[3] -> $r->[2] $r->[4]";
	} else {
		$r->[2] ||= "";
		$s = "$r->[2]";
	}
	return "$d $s";
}

1;
