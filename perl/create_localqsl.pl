#!/usr/bin/perl
#
# Implement a 'GO' database list
#
# Copyright (c) 2003 Dirk Koopman G1TLH
#
# $Id$
#

# search local then perl directories
BEGIN {
	use vars qw($root);
	
	# root of directory tree for this system
	$root = "/spider"; 
	$root = $ENV{'DXSPIDER_ROOT'} if $ENV{'DXSPIDER_ROOT'};
	
	unshift @INC, "$root/perl";	# this IS the right way round!
	unshift @INC, "$root/local";
}

use strict;

use IO::File;
use DXVars;
use DXUtil;
use Spot;
use DXDb;

my $end = 0;
$SIG{TERM} = $SIG{INT} = sub { $end++ };

my $qslfn = "localqsl";

$main::systime = time;

DXDb::load();
my $db = DXDb::getdesc($qslfn);
unless ($db) {
	DXDb::new($qslfn);
	DXDb::load();
	$db = DXDb::getdesc($qslfn);
}

die "cannot load $qslfn $!" unless $db;

my $base = "$root/data/spots";

opendir YEAR, $base or die "$base $!";
foreach my $year (sort readdir YEAR) {
	next if $year =~ /^\./;
	my $baseyear = "$base/$year";
	opendir DAY,  $baseyear or die "$baseyear $!";
	foreach my $day (sort readdir DAY) {
		next unless $day =~ /dat$/;
		my $fn = "$baseyear/$day";
		my $f = new IO::File $fn  or die "$fn ($!)"; 
		print "doing: $fn\n";
		while (<$f>) {
			if (/(QSL|VIA)/i) {
				my ($freq, $call, $t, $comment, $by, @rest) = split /\^/;
				my $value = $db->getkey($call) || "";
				my $newvalue = update($value, $call, $t, $comment, $by);
				if ($newvalue ne $value) {
					$db->putkey($call, $newvalue);
				}
			}
		}
		$f->close;
	}
}

DXDb::closeall();
exit(0);

sub update
{
	my ($line, $call, $t, $comment, $by) = @_;
	my @lines = split /\n/, $line;
	my @in;
	
	# decode the lines
	foreach my $l (@lines) {
		my ($date, $time, $oby, $ocom) = $l =~ /^(\s?\S+)\s+(\s?\S+)\s+by\s+(\S+):\s+(.*)$/;
		if ($date) {
			my $ot = cltounix($date, $time);
			push @in, [$ot, $oby, $ocom];
		} else {
			print "Cannot decode $call: $l\n";
			$DB::single = 1;
		}
		
	}
	
	# is this newer than the earliest one?
	if (@in && $in[0]->[0] < $t) {
		@in = grep {$_->[1] ne $by} @in;
	}
	unshift @in, [$t, $by, $comment];
	pop @in, if @in > 5;
	return join "\n", (map {(cldatetime($_->[0]) . " by $_->[1]: $_->[2]")} @in);
}

