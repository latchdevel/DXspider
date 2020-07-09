#!/usr/bin/env perl
#
# Convert users.v2 or .v3 to JSON .v3j format
#
# It is believed that this can be run at any time...
#
# Copyright (c) 2020 Dirk Koopman G1TLH
#
#
# 

# make sure that modules are searched in the order local then perl

BEGIN {
	# root of directory tree for this system
	$root = "/spider"; 
	$root = $ENV{'DXSPIDER_ROOT'} if $ENV{'DXSPIDER_ROOT'};
    unshift @INC, "$root/perl";     # this IS the right way round!
	unshift @INC, "$root/local";
}

use strict;

use SysVar;
use DXUser;
use DXUtil;
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
my $ofn = localdata("$fn.v3j");
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

if (-e $ofn) {
	my $nfn = localdata("$fn.v3j.new");
	say "You appear to have (or are using) $ofn, creating $nfn instead";
	$ofn = $nfn;
} else {
	$ofn = $ofn;
	say "using $ofn for output";
}


# do a conversion if required
if ($convert) {
	my ($key, $val, $action, $count, $err) = ('','',0,0,0);
	my $ta = [gettimeofday];
	my $ofh = IO::File->new(">$ofn") or die "cannot open $ofn ($!)\n";
		
	my %oldu;
	my %newu;
	
	LogDbg('',"Converting the User from V$convert format to $fn.v3j ");
	LogDbg('',"This will take a while, maybe as much as 30 secs on very slow disks and/or machines");
	my $idbm = tie (%oldu, 'DB_File', localdata("users.v$convert"), O_RDONLY, 0666, $DB_BTREE) or confess "can't open user file: $fn.v$convert ($!) [rebuild it from user_asc?]";
	my $odbm = tie (%newu, 'DB_File', $ofn, O_CREAT|O_RDWR, 0666, $DB_BTREE) or confess "can't open user file: $ofn ($!)";
	for ($action = R_FIRST; !$idbm->seq($key, $val, $action); $action = R_NEXT) {
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
				$newu{$ref->{call}} = $json->encode($ref);
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
	untie %oldu;
	undef $idbm;
	untie %newu;
	undef $odbm;
	my $t = _diffms($ta);
	LogDbg('',"Conversion from users.v$convert to $ofn completed $count records $err errors $t mS");
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
		LogDbg('err', "asc_decode: on '$s' $@");
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
