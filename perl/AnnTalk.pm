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

use vars qw(%dup $duplth $dupage $filterdef);

$duplth = 60;					# the length of text to use in the deduping
$dupage = 5*24*3600;			# the length of time to hold spot dups
$filterdef = bless ([
			  # tag, sort, field, priv, special parser 
			  ['by', 'c', 0],
			  ['dest', 'c', 1],
			  ['info', 't', 2],
			  ['group', 't', 3],
			  ['wx', 't', 5],
			  ['origin', 'c', 7, 4],
			  ['origin_dxcc', 'c', 10],
			  ['origin_itu', 'c', 11],
			  ['origin_itu', 'c', 12],
			  ['by_dxcc', 'n', 7],
			  ['by_itu', 'n', 8],
			  ['by_zone', 'n', 9],
			  ['channel', 'n', 6],
			 ], 'Filter::Cmd');


# enter the spot for dup checking and return true if it is already a dup
sub dup
{
	my ($call, $to, $text) = @_; 

	chomp $text;
	unpad($text);
	$text =~ s/[\\\%]\d+//g;
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

