#
# module to timed tasks
#
# Copyright (c) 1998 - Dirk Koopman G1TLH
#
# $Id$
#

package DXCron;

use DXVars;
use DXUtil;
use DXM;
use DXDebug;
use FileHandle;
use Carp;

use strict;

use vars qw{@crontab $mtime $lasttime};

@crontab = ();
$mtime = 0;
$lasttime = 0;


my $fn = "$main::cmd/crontab";
my $localfn = "$main::localcmd/crontab";

# cron initialisation / reading in cronjobs
sub init
{
	my $t;
	
	if (-e $localfn) {
		if (-e $localfn && ($t = -M $localfn) != $mtime) {
			cread($localfn);
			$mtime = $t;
		}
		return;
	}
	if (($t = -M $fn) != $mtime) {
		cread($fn);
		$mtime = $t;
	}
}

# read in a cron file
sub cread
{
	my $fn = shift;
	my $fh = new FileHandle;
	my $line = 0;

	dbg('cron', "reading $fn\n");
	open($fh, $fn) or confess("can't open $fn $!");
	@crontab = ();           # clear out the old stuff
	while (<$fh>) {
		$line++;
		
		next if /^\s*#/o or /^\s*$/o;
		my ($min, $hour, $mday, $month, $wday, $cmd) = /^\s*(\w+)\s+(\w+)\s+(\w+)\s+(\w+)\s+(\w+)\s+(.+)$/o;
		next if !$min;
		my $ref = bless {};
		my $err;
		
		$err |= parse($ref, 'min', $min, 0, 60);
		$err |= parse($ref, 'hour', $hour, 0, 23);
		$err |= parse($ref, 'mday', $mday, 1, 31);
		$err |= parse($ref, 'month', $month, 1, 12, "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec");
		$err |= parse($ref, 'wday', $wday, 0, 6, "sun", "mon", "tue", "wed", "thu", "fri", "sat");
		if (!$err) {
			$ref->{cmd} = $cmd;
			push @crontab, $ref;
			dbg('cron', "adding $_\n");
		} else {
			dbg('cron', "error on line $line '$_'\n");
		}
	}
	close($fh);
}

sub parse
{
	my $ref = shift;
	my $sort = shift;
	my $val = shift;
	my $low = shift;
	my $high = shift;
	my @req;

	# handle '*' values
	if ($val eq '*') {
		$ref->{$sort} = 0;
		return 0;
	}

	# handle comma delimited values
	my @comma = split /,/o, $val;
	for (@comma) {
		my @minus = split /-/o;
		if (@minus == 2) {
			return 1 if $minus[0] < $low || $minus[0] > $high;
			return 1 if $minus[1] < $low || $minus[1] > $high;
			my $i;
			for ($i = $minus[0]; $i <= $minus[1]; ++$i) {
				push @req, 0 + $i; 
			}
		} else {
			return 1 if $_ < $low || $_ > $high;
			push @req, 0 + $_;
		}
	}
	return 0;
}

# process the cronjobs
sub process
{
	my $now = $main::systime;
	
	if ($now - $lasttime >= 60) {
		my ($sec, $min, $hour, $mday, $mon, $wday) = (gmtime($main::systime))[0-4,6];
		
		$lasttime = $now;
	}
}

1;
__END__
