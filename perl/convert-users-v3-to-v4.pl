#!/usr/bin/env perl
#
# Convert users.v2 or .v3 to JSON .v4 format
#
# It is believed that this can be run at any time...
#
# Copyright (c) 2020 Dirk Koopman G1TLH
#
#
# 

# make sure that modules are searched in the order local then perl

our $root;

BEGIN {
	# root of directory tree for this system
	$root = "/spider"; 
	$root = $ENV{'DXSPIDER_ROOT'} if $ENV{'DXSPIDER_ROOT'};
    unshift @INC, "$root/perl";     # this IS the right way round!
	unshift @INC, "$root/local";
}

use strict;

use DXVars;
use DXUser;
use JSON;
use Data::Structure::Util qw(unbless);
use Time::HiRes qw(gettimeofday tv_interval);
use IO::File;
use File::Copy;
use Carp;
use DB_File;

use 5.10.1;

my $ufn;
my $fn = "users";

my $json = JSON->new()->canonical(1);
my $ofn = localdata("$fn.v4");
my $convert;

eval {
	require Storable;
};

if ($@) {
	if ( ! -e localdata("$fn.v3") && -e localdata("$fn.v2") ) {
		$convert = 2;
	}
	LogDbg('',"the module Storable appears to be missing!!");
	LogDbg('',"trying to continue in compatibility mode (this may fail)");
	LogDbg('',"please install Storable from CPAN as soon as possible");
}
else {
	import Storable qw(nfreeze thaw);
	$convert = 3 if -e localdata("users.v3") && !-e $ufn;
}

die "need to have a $fn.v2 or (preferably) a $fn.v3 file in /spider/data or /spider/local_data\n" unless $convert;

if (-e $ofn || -e "$ofn.n") {
	my $nfn = localdata("$fn.v4.json");
	say "You appear to have (or are using) $ofn, creating $nfn instead";
	$ofn = $nfn;
} else {
	$ofn = "$ofn.n";
	say "using $ofn.n for output";
}


# do a conversion if required
if ($convert) {
	my ($key, $val, $action, $count, $err) = ('','',0,0,0);
	my $ta = [gettimeofday];
	my $ofh = IO::File->new(">$ofn") or die "cannot open $ofn ($!)\n";
	my $oldfn = localdata("users.v$convert");
			
	my %oldu;
	LogDbg('',"Converting the User File from V$convert to $fn.v4 ");
	LogDbg('',"This will take a while, maybe as much as 10 secs");
	my $odbm = tie (%oldu, 'DB_File', $oldfn, O_RDONLY, 0666, $DB_BTREE) or confess "can't open user file: $oldfn ($!) [rebuild it from user_asc?]";
	for ($action = R_FIRST; !$odbm->seq($key, $val, $action); $action = R_NEXT) {
		my $ref;
		if ($convert == 3) {
			eval { $ref = storable_decode($val) };
		}
		else {
			eval { $ref = asc_decode($val) };
		}
		unless ($@) {
			if ($ref) {
				unbless $ref;
				$ofh->print("$ref->{call}\t" . $json->encode($ref) . "\n");
				$count++;
			}
			else {
				$err++
			}
		}
		else {
			Log('err', "DXUser: error decoding $@");
		}
	} 
	undef $odbm;
	untie %oldu;
	my $t = _diffms($ta);
	LogDbg('',"Conversion from $oldfn to $ofn completed $count records $err errors $t mS");
	$ofh->close;
}

exit 0;

sub asc_decode
{
	my $s = shift;
	my $ref;
	$s =~ s/\%([0-9A-F][0-9A-F])/chr(hex($1))/eg;
	eval '$ref = ' . $s;
	if ($@) {
		LogDbg('err', "DXUser::asc_decode: on '$s' $@");
		$ref = undef;
	}
	return $ref;
}

sub storable_decode
{
	my $ref;
	$ref = thaw(shift);
	return $ref;
}

sub LogDbg
{
	my (undef, $s) = @_;
	say $s;
}

sub Log
{
	say shift;
}

# find the correct local_data directory
# basically, if there is a local_data directory with this filename and it is younger than the
# equivalent one in the (system) data directory then return that name rather than the system one
sub localdata
{
	my $ifn = shift;
	my $ofn = "$root/local_data/$ifn";
	my $tfn;
        
	if (-e "$root/local_data") {
		$tfn = "$main::data/$ifn";
		if ((-e $tfn) && (-e $ofn)) {
			$ofn = $tfn if -M $ofn < -M $tfn;
		}
		else {
			$ofn = $tfn if -e $tfn;
		}
	}

	return $ofn;
}
# measure the time taken for something to happen; use Time::HiRes qw(gettimeofday tv_interval);
sub _diffms
{
    my $ta = shift;
    my $tb = shift || [gettimeofday];
    my $a = int($ta->[0] * 1000) + int($ta->[1] / 1000);
    my $b = int($tb->[0] * 1000) + int($tb->[1] / 1000);
    return $b - $a;
}

