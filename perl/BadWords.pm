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
use DXHash;
use IO::File;

use vars qw($badword);

my $oldfn = "$main::data/badwords";
$badword = new DXHash "badword";

use vars qw($VERSION $BRANCH);
$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /\d+\.\d+\.(\d+)\.(\d+)/ ) || 0;
$main::build += $VERSION;
$main::branch += $BRANCH;

# load the badwords file
sub load
{
	my @out;
	return unless -e $oldfn;
	my $fh = new IO::File $oldfn;
	
	if ($fh) {
		while (<$fh>) {
			chomp;
			next if /^\s*\#/;
			my @list = split " ";
			for (@list) {
				$badword->add($_);
			}
		}
		$fh->close;
		$badword->put;
		unlink $oldfn;
	} else {
		my $l = "can't open $oldfn $!";
		dbg($l);
		push @out, $l;
	}
	return @out;
}

# check the text against the badwords list
sub check
{
	return grep { $badword->in($_) } split(/\b/, lc shift);
}

1;
