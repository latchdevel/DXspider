#
# Announce and Talk Handling routines
#
# Copyright (c) 2000 Dirk Koopman
#
# $Id$
#

package AnnTalk;

use strict;

use DXUtil;
use DXDebug;

use vars qw(%dup $duplth $dupage);

%dup = ();						# the duplicates hash
$duplth = 60;					# the length of text to use in the deduping
$dupage = 24*3600;               # the length of time to hold spot dups

# enter the spot for dup checking and return true if it is already a dup
sub dup
{
	my ($call, $to, $text) = @_; 
	my $d = $main::systime;

	chomp $text;
	unpad($text);
	$text = substr($text, 0, $duplth) if length $text > $duplth; 
	my $dupkey = "$call|$to|$text";
	return 1 if exists $dup{$dupkey};
	$dup{$dupkey} = $d;         # in seconds (to the nearest minute)
	return 0; 
}

# called every hour and cleans out the dup cache
sub process
{
	my $cutoff = $main::systime - $dupage;
	while (my ($key, $val) = each %dup) {
		delete $dup{$key} if $val < $cutoff;
	}
}

sub listdups
{
	my @out;
	for (sort { $dup{$a} <=> $dup{$b} } keys %dup) {
		my $val = $dup{$_};
		push @out, "$_ = $val (" . cldatetime($val) . ")";
	}
	return @out;
}


1; 

