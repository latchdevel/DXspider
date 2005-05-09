#!/usr/bin/perl
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
	$main::root = "/spider";
	$main::root = $ENV{'DXSPIDER_ROOT'} if $ENV{'DXSPIDER_ROOT'};
	
	unshift @INC, "$root/perl";     # this IS the right way round!
	unshift @INC, "$root/local";
}

use strict;

use DXUtil;
use Spot;
use DBI;

our $root;

Spot::init();

my $dbh;
my $sort = lc shift || 'sqlite';

if ($sort eq 'sqlite') {
	unlink "$root/data/spider.db";
	$dbh = DBI->connect("dbi:SQLite:dbname=$root/data/spider.db","","")
		or die "cannot open $root/data/spider.db";
	$dbh->do("PRAGMA default_synchronous = OFF");
} elsif ($sort eq 'mysql') {
	$dbh = DBI->connect("dbi:mysql:dbname=spider","spider","spider")
		or die $DBI::errstr;
} elsif ($sort eq 'pg') {
	$dbh = DBI->connect("dbi:Pg:dbname=spider","postgres","")
		or die $DBI::errstr;
} else {
	die "invalid database type: $sort";
}

$dbh->{PrintError} = 0;
$dbh->{PrintWarn} = 0;

opendir DIR, "$root/data/spots" or die "No spot directory $!\n";
my @years = grep {/^\d/} readdir DIR;
closedir DIR;

my $start = time;

eval { $dbh->do("drop table spots");};

$dbh->do("CREATE TABLE spots (freq real,
spotted varchar(255),
t int,
comment varchar(255),
spotter varchar(255),
spotted_dxcc int,
spotter_dxcc int,
origin varchar(255),
spotted_itu int,
spotted_cq int,
spotter_itu int,
spotter_cq int,
spotted_state varchar(2),
spotter_state varchar(2)
)");

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
				if ($sort eq 'pg' && $count && $count % 100 == 0) {
					$dbh->commit;
					$dbh->begin_work;
				}
				my @s = split /\^/;
				if ($sort eq 'pg') {
					push @s, '' while @s < 14;
					$s[5]+=0;
					$s[6]+=0;
					$s[8]+=0;
					$s[9]+=0;
					$s[10]+=0;
					$s[11]+=0;
				} else {
					push @s, undef while @s < 14;
				}
				eval { $sth->execute(@s) };
				if ($@) {
					print DBI::neat_list(@s);
					$dbh->rollback;
					$dbh->begin_work;
				}
				$count++;
			}
			$dbh->commit;
		}
		print " $count\n";
	}
}
print "\n";
$sth->finish;

my $secs = time - $start;
print "Load took $secs\n";
$secs = time;

$dbh->do("CREATE INDEX spotted_idx on spots(spotted)");

my $secs = time - $start;
print "Spotted index took $secs\n";
$secs = time;

$dbh->do("CREATE INDEX t_idx on spots(t)");

my $secs = time - $start;
print "T index took $secs\n";
$secs = time;

$dbh->disconnect;



