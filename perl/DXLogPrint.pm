#
# Log Printing routines
#
# Copyright (c) - 1998 Dirk Koopman G1TLH
#
# $Id$
#

package DXLog;

use IO::File;
use DXVars;
#use DXDebug ();
use DXUtil;
use DXLog;
use Julian;

use strict;

use vars qw($VERSION $BRANCH);
$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /\d+\.\d+\.(\d+)\.(\d+)/,(0,0));
$main::build += $VERSION;
$main::branch += $BRANCH;

#
# print some items from the log backwards in time
#
# This command outputs a list of n lines starting from time t with $pattern tags
#
sub print
{
	my $fcb = $DXLog::log;
	my $from = shift || 0;
	my $to = shift || 20;
	my $jdate = $fcb->unixtoj(shift);
	my $pattern = shift;
	my $who = uc shift;
	my $search;
	my @in;
	my @out = ();
	my $eval;
	my $tot = $from + $to;
	my $hint = "";
	    
	if ($pattern) {
		$hint = "m{\\Q$pattern\\E}i";
	} else {
		$hint = "!m{ann|rcmd|talk|chat}";
	}
	if ($who) {
		$hint .= ' && ' if $hint;
		$hint .= 'm{\\Q$who\\E}i';
	} 
	$hint = "next unless $hint" if $hint;
	$hint .= ";next unless /^\\d+\\^$pattern\\^/" if $pattern;
	$hint ||= "";
	
	$eval = qq(while (<\$fh>) {
				   $hint;
				   chomp;
				   push \@tmp, \$_;
			   } );
	
	$fcb->close;                                      # close any open files

	my $fh = $fcb->open($jdate); 
 L1: for (;@in < $to;) {
		my $ref;
		if ($fh) {
			my @tmp;
			eval $eval;               # do the search on this file
			return ("Log search error", $@) if $@;
			@in = (@tmp, @in);
			if (@in > $to) {
				@in = splice @in, -$to, $to;
				last L1;
			} 
		}
		$fh = $fcb->openprev();      # get the next file
		last if !$fh;
	}
	for (@in) {
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
		if ($r->[2] eq 'in') {
			$r->[5] ||= "";
			$s = "$r->[4] (priv: $r->[3]) rcmd: $r->[5]";
		} else {
			$r->[4] ||= "";
			$s = "$r->[3] reply: $r->[4]";
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
