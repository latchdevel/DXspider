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
use DXDebug ();
use DXUtil;
use DXLog;
use Julian;
use Carp;

use strict;

#
# print some items from the log backwards in time
#
# This command outputs a list of n lines starting from time t with $pattern tags
#
sub print
{
	my $self = $DXLog::log;
	my $from = shift;
	my $to = shift;
	my @date = $self->unixtoj(shift);
	my $pattern = shift;
	my $who = uc shift;
	my $search;
	my @in;
	my @out;
	my $eval;
	my $count;
	    
	$search = '1' unless $pattern || $who;
	$search = "\$ref->[1] =~ /$pattern/" if $pattern;
	$search .= ' && ' if $pattern && $who;
	$search .= "(\$ref->[2] =~ /$who/ || \$ref->[3] =~ /$who/)" if $who;
	$eval = qq(
			   my \$c;
			   my \$ref;
			   for (\$c = \$#in; \$c >= 0; \$c--) {
					\$ref = \$in[\$c];
					if ($search) {
						\$count++;
						next if \$count < $from;
						push \@out, print_item(\$ref);
						last if \$count >= \$to;                  # stop after n
					}
				}
			  );
	
	$self->close;                                      # close any open files

	my $fh = $self->open(@date); 
	for ($count = 0; $count < $to; ) {
		my @spots = ();
		if ($fh) {
			while (<$fh>) {
				chomp;
				push @in, [ split '\^' ];
			}
			eval $eval;               # do the search on this file
			last if $count >= $to;                  # stop after n
			return ("Log search error", $@) if $@;
		}
		$fh = $self->openprev();      # get the next file
		last if !$fh;
	}
	
	return @out if defined @out;
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
