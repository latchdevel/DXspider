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
			  ['origin', 'c', 4],
			  ['wx', 't', 5],
			  ['channel', 'c', 6],
			  ['by_dxcc', 'nc', 7],
			  ['by_itu', 'ni', 8],
			  ['by_zone', 'nz', 9],
			  ['origin_dxcc', 'nc', 10],
			  ['origin_itu', 'ni', 11],
			  ['origin_zone', 'nz', 12],
			 ], 'Filter::Cmd');

use vars qw($VERSION $BRANCH);
$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /\d+\.\d+\.(\d+)\.(\d+)/ ) || 0;
$main::build += $VERSION;
$main::branch += $BRANCH;

# enter the spot for dup checking and return true if it is already a dup
sub dup
{
	my ($call, $to, $text) = @_; 

	chomp $text;
	unpad($text);
	$text =~ s/\%([0-9A-F][0-9A-F])/chr(hex($1))/eg;
	$text = substr($text, 0, $duplth) if length $text > $duplth; 
	$text = pack("C*", map {$_ & 127} unpack("C*", $text));
	$text =~ s/[^a-zA-Z0-9]//g;
	my $dupkey = "A$to|\L$text";
	return DXDupe::check($dupkey, $main::systime + $dupage);
}

sub listdups
{
	return DXDupe::listdups('A', $dupage, @_);
}


1; 

