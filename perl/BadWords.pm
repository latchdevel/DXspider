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
	my $s = uc shift;
	
	for (split(/\s+/, $s)) {
		s/[^\w]//g;
		return $_ if $badword->in($_);
		s/\'?S$//;
		return $_ if $badword->in($_);
	}
	
	# look for a few of the common ones with spaces and stuff
	if ($s =~ /F[\s\W]*U[\s\W]*C[\s\W]*K/) {
		return "FUCK";
	} elsif ($s =~ /C[\s\W]*U[\s\W]*N[\s\W]*T/) {
		return "CUNT";
	} elsif ($s =~ /W[\s\W]*A[\s\W]*N[\s\W]*K/) {
		return "WANK";
	} elsif ($s =~ /C[\s\W]*[0O][\s\W]*C[\s\W]*K/) {
		return "COCK";
	} elsif ($s =~ /S[\s\W]*H[\s\W]*[I1][\s\W]*T/) {
		return "SHIT";
	} elsif ($s =~ /P[\s\W]*[I1][\s\W]*S[\s\W]*S/) {
		return "PISS";
	} elsif ($s =~ /B[\s\W]*[O0][\s\W]*L[\s\W]*L[\s\W]*[O0][\s\W]*[CK]/) {
		return "BOLLOCKS";
	}
	
	return ();
}

1;
