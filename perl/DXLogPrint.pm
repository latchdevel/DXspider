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
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /\d+\.\d+\.(\d+)\.(\d+)/ ) || 0;
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
	my $count;
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
		$hint = "!m{ann|rcmd|talk}";
	}
	if ($who) {
		if ($hint) {
			$hint .= ' && ';
		}
		$hint .= 'm{\\Q$who\\E}i';
	} 
	$hint = "next unless $hint" if $hint;
	
	$eval = qq(
			   \@in = ();
			   while (<\$fh>) {
				   $hint;
				   chomp;
				   push \@in, \$_;
				   shift \@in, if \@in > $tot;
			   }
		   );
	
	$fcb->close;                                      # close any open files

	my $fh = $fcb->open($jdate); 
	L1: for ($count = 0; $count < $to; ) {
		my $ref;
		if ($fh) {
			eval $eval;               # do the search on this file
			return ("Log search error", $@) if $@;
			my @tmp;
			while (@in) {
				last L1 if $count >= $to;
				my $ref = [ split /\^/, shift @in ];
				next if defined $pattern && $ref->[1] ne $pattern;
				push @tmp, print_item($ref);
				$count++;
			}
			@out = (@tmp, @out);
		}
		$fh = $fcb->openprev();      # get the next file
		last if !$fh;
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
	my @ref = @$r;
	my $d = atime($ref[0]);
	my $s = 'undef';
	
	if ($ref[1] eq 'rcmd') {
		if ($ref[2] eq 'in') {
			$s = "$ref[4] (priv: $ref[3]) rcmd: $ref[5]";
		} else {
			$s = "$ref[3] reply: $ref[4]";
		}
	} elsif ($ref[1] eq 'talk') {
		$s = "$ref[3] -> $ref[2] ($ref[4]) $ref[5]";
	} elsif ($ref[1] eq 'ann') {
		$s = "$ref[3] -> $ref[2] $ref[4]";
	} else {
		$s = "$ref[2]";
	}
	return "$d $s";
}

1;
