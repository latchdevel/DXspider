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
use DXDupe;
use DXVars;

use vars qw(%dup $duplth $dupage);

$duplth = 60;					# the length of text to use in the deduping
$dupage = 5*24*3600;			# the length of time to hold spot dups


# enter the spot for dup checking and return true if it is already a dup
sub dup
{
	my ($call, $to, $text) = @_; 

	chomp $text;
	unpad($text);
	$text =~ s/[^a-zA-Z0-9]//g;
	$text = substr($text, 0, $duplth) if length $text > $duplth; 
	my $dupkey = "A$to|\L$text";
	return DXDupe::check($dupkey, $main::systime + $dupage);
}

sub listdups
{
	return DXDupe::listdups('A', $dupage, @_);
}


1; 

