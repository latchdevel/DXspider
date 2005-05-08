#
# $Id$
#
# Copyright (c) 2005 Dirk Koopman G1TLH
#
# Load all the spots you have into the spider.sdb SQLite
# SQL database.
# 
BEGIN {

	sub mkver {};
	
	# root of directory tree for this system
	$root = "/spider";
	$root = $ENV{'DXSPIDER_ROOT'} if $ENV{'DXSPIDER_ROOT'};
	
	unshift @INC, "$root/perl";     # this IS the right way round!
	unshift @INC, "$root/local";
}

use DXUtil;
use Spot;
use DBI;
use DBD::SQLite;

Spot::init();

my $dbh = DBI->connect("dbi:SQLite:dbname=$root/data/spider.sdb","","")
	or die "cannot open $root/data/spider.sdb";

opendir DIR, "$root/data/spots" or die "No spot directory $!\n";
my @years = grep {/^\d/} readdir DIR;
closedir DIR;

$dbh->do("delete from spots");

my $sth = $dbh->prepare("insert into spots values (?,?,?,?,?,?,?,?,?,?,?,?,?,?)") or die "prepare\n";

foreach my $year (@years) {
	opendir DIR, "$root/data/spots/$year" or next;
	my @days = grep {/^\d+\.dat/} readdir DIR;
	closedir DIR;
	my $j = Julian::Day->new(time);
	for (@days) {
		my ($day) = /^(\d+)/;
		my $count;
		$j->[0] = $year;
		$j->[1] = $day-0;
		printf "\rdoing $year %03d", $day;
		my $fh = $Spot::fp->open($j); # get the next file
		if ($fh) {
			$dbh->begin_work;
			while (<$fh>) {
				my @s = split /\^/;
				push @s, undef while @s < 14;
				$sth->execute(@s);
				$count++;
			}
			$dbh->commit;
		}
		print " $count\n";
	}
}
print "\n";
$sth->finish;
$dbh->disconnect;


