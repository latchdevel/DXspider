#!/usr/bin/env perl
#
# Implement a 'GO' database list
#
# Copyright (c) 2003 Dirk Koopman G1TLH
#
#
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
use SysVar;
use DXUtil;
use Spot;
use QSL;

use vars qw($end $lastyear $lastday $lasttime);

$end = 0;
$SIG{TERM} = $SIG{INT} = sub { $end++ };

my $qslfn = "qsl";

$main::systime = time;

unlink "$data/qsl.v2";
unlink "$local_data/qsl.v2";

QSL::init(1) or die "cannot open QSL file";

my $base = localdata("spots");

my $tu = 0;
my $tr = 0;

opendir YEAR, $base or die "$base $!";
foreach my $year (sort readdir YEAR) {
	next if $year =~ /^\./;
	
	my $baseyear = "$base/$year";
	opendir DAY,  $baseyear or die "$baseyear $!";
	foreach my $day (sort readdir DAY) {
		next unless $day =~ /(\d+)\.dat$/;
		my $dayno = $1 + 0;
		
		my $fn = "$baseyear/$day";
		my $f = new IO::File $fn  or die "$fn ($!)"; 
		print "doing: $fn";
		my $u = 0;
		my $r = 0;
		while (<$f>) {
			last if $end;
			if (/(QSL|VIA)/i) {
				my ($freq, $call, $t, $comment, $by, @rest) = split /\^/;
				my $q = QSL::get($call) || new QSL $call;
				if ($q) {
					$q->update($comment, $t, $by);
					$lasttime = $t;
					++$u;
					++$tu;
				}
			}
			++$r;
			++$tr;
		}
		printf " - Spots read %8d QSLs %6d\n", $r, $u;
		$f->close;
		last if $end;
	}
	last if $end;
}

print "Total Spots read: $tr - QSLs found: $tu\n";

QSL::finish();

exit(0);


