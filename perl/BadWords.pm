#
# Search for bad words in strings
#
# Copyright (c) 2000 Dirk Koopman
#
# $Id$
#

package BadWords;

use strict;

use DXUtil;
use DXVars;
use IO::File;

use vars qw(%badwords $fn);

$fn = "$main::data/badwords";
%badwords = ();

use vars qw($VERSION $BRANCH);
$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /\d+\.\d+\.(\d+)\.(\d+)/ ) || 0;
$main::build += $VERSION;
$main::branch += $BRANCH;

# load the badwords file
sub load
{
	my @out;
	return unless -e $fn;
	my $fh = new IO::File $fn;
	
	if ($fh) {
		%badwords = ();
		while (<$fh>) {
			chomp;
			next if /^\s*\#/;
			my @list = split " ";
			for (@list) {
				$badwords{lc $_}++;
			}
		}
		$fh->close;
	} else {
		my $l = "can't open $fn $!";
		dbg('err', $l);
		push @out, $l;
	}
	return @out;
}

# check the text against the badwords list
sub check
{
	return grep { $badwords{$_} } split(/\b/, lc shift);
}

1;
