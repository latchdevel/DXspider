#
# Package to handle US Callsign -> City, State translations
#
# Copyright (c) 2002 Dirk Koopman G1TLH
#
# 

package USDB;

use strict;

use DXVars;
use DB_File;
use File::Copy;
use DXDebug;
#use Compress::Zlib;

use vars qw($VERSION $BRANCH);
$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /\d+\.\d+\.(\d+)\.(\d+)/,(0,0));
$main::build += $VERSION;
$main::branch += $BRANCH;

use vars qw(%db $present $dbfn);

$dbfn = "$main::data/usdb.v1";

sub init
{
	end();
	if (tie %db, 'DB_File', $dbfn, O_RDWR, 0664, $DB_BTREE) {
		$present = 1;
		return "US Database loaded";
	}
	return "US Database not loaded";
}

sub end
{
	return unless $present;
	untie %db;
	undef $present;
}

sub get
{
	return () unless $present;
	my $ctyn = $db{$_[0]};
	my @s = split /\|/, $db{$ctyn} if $ctyn;
	return @s;
}

sub _add
{
	my ($db, $call, $city, $state) = @_;
	
	# lookup the city 
	my $s = uc "$city|$state";
	my $ctyn = $db->{$s};
	unless ($ctyn) {
		my $no = $db->{'##'} || 1;
		$ctyn = "#$no";
		$db->{$s} = $ctyn;
		$db->{$ctyn} = $s; 
		$no++;
		$db->{'##'} = "$no";
	}
	$db->{uc $call} = $ctyn; 
}

sub add
{
	_add(\%db, @_);
}

sub getstate
{
	return () unless $present;
	my @s = get($_[0]);
	return @s ? $s[1] : undef;
}

sub getcity
{
	return () unless $present;
	my @s = get($_[0]);
	return @s ? $s[0] : undef;
}

sub del
{
	my $call = uc shift;
	delete $db{$call};
}

#
# load in / update an existing DB with a standard format (GZIPPED)
# "raw" file.
#
# Note that this removes and overwrites the existing DB file
# You will need to init again after doing this
# 

sub load
{
	return "Need a filename" unless @_;
	
	# create the new output file
	my $a = new DB_File::BTREEINFO;
	$a->{psize} = 4096 * 2;
	my $s = 0;

	# guess a cache size
	for (@_) {
		my $ts = -s;
		$s = $ts if $ts > $s;
	}
	if ($s > 1024 * 1024) {
		$a->{cachesize} = int($s / (1024*1024)) * 3 * 1024 * 1024;
	}

#	print "cache size " . $a->{cachesize} . "\n";
	
	my %dbn;
	if (-e $dbfn ) {
		copy($dbfn, "$dbfn.new") or return "cannot copy $dbfn -> $dbfn.new $!";
	}
	
	tie %dbn, 'DB_File', "$dbfn.new", O_RDWR|O_CREAT, 0664, $a or return "cannot tie $dbfn.new $!";
	
	# now write away all the files
	my $count = 0;
	for (@_) {
		my $ofn = shift;

		return "Cannot find $ofn" unless -r $ofn;
		
		# conditionally handle compressed files (don't cha just lurv live code, this is
		# a rave from the grave and is "in memoriam Flossie" the ICT 1301G I learnt on.
		# {for pedant computer historians a 1301G is an ICT 1301A that has been 
		# Galdorised[tm] (for instance had decent IOs and a 24 pre-modify instruction)}
		my $nfn = $ofn;
		if ($nfn =~ /.gz$/i) {
			my $gz;
			eval qq{use Compress::Zlib; \$gz = gzopen(\$ofn, "rb")};
			return "Cannot read compressed files $@ $!" if $@ || !$gz;
			$nfn =~ s/.gz$//i;
			my $of = new IO::File ">$nfn" or return "Cannot write to $nfn $!";
			my ($l, $buf);
			$of->write($buf, $l) while ($l = $gz->gzread($buf));
			$gz->gzclose;
			$of->close;
			$ofn = $nfn;
		}

		my $of = new IO::File "$ofn" or return "Cannot read $ofn $!";

		while (<$of>) {
			my $l = $_;
			$l =~ s/[\r\n]+$//;
			my ($call, $city, $state) = split /\|/, $l;

			_add(\%dbn, $call, $city, $state);
			
			$count++;
		}
		$of->close;
		unlink $nfn;
	}
	
	untie %dbn;
	rename "$dbfn.new", $dbfn;
	return "$count records";
}

1;
