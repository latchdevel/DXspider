#!/usr/bin/perl -w
#
# Local 'autoqsl' module for DXSpider
#
# Copyright (c) 2003 Dirk Koopman G1TLH
#

package QSL;

use strict;
use DXVars;
use DXUtil;
use DB_File;
use DXDebug;
use Prefix;

use vars qw($qslfn $dbm);
$qslfn = 'qsl';
$dbm = undef;

localdata_mv("$qslfn.v1");

sub init
{
	my $mode = shift;
	my $ufn = localdata("$qslfn.v1");

	Prefix::load() unless Prefix::loaded();
	
	eval {
		require Storable;
	};
	
	if ($@) {
		dbg("Storable appears to be missing");
		dbg("In order to use the QSL feature you must");
		dbg("load Storable from CPAN");
		return undef;
	}
	import Storable qw(nfreeze freeze thaw);
	my %u;
	if ($mode) {
		$dbm = tie (%u, 'DB_File', $ufn, O_CREAT|O_RDWR, 0666, $DB_BTREE) or confess "can't open qsl file: $qslfn ($!)";
	} else {
		$dbm = tie (%u, 'DB_File', $ufn, O_RDONLY, 0666, $DB_BTREE) or confess "can't open qsl file: $qslfn ($!)";
	}
	return $dbm;
}

sub finish
{
	undef $dbm;
}

sub new
{
	my ($pkg, $call) = @_;
	return bless [uc $call, []], $pkg;
}

# the format of each entry is [manager, times found, last time, last reporter]
sub update
{
	return unless $dbm;
	my $self = shift;
	my $line = shift;
	my $t = shift;
	my $by = shift;
	my $changed;
			
	foreach my $man (split /\b/, uc $line) {
		my $tok;
		
		if (is_callsign($man)) {
			my @pre = Prefix::extract($man);
			$tok = $man if @pre && $pre[0] ne 'Q';
		} elsif ($man =~ /^BUR/) {
			$tok = 'BUREAU';
		} elsif ($man eq 'HC' || $man =~ /^HOM/ || $man =~ /^DIR/) {
			$tok = 'HOME CALL';
		} elsif ($man =~ /^QRZ/) {
			$tok = 'QRZ.com';
		}
		if ($tok) {
			my ($r) = grep {$_->[0] eq $tok} @{$self->[1]};
			if ($r) {
				$r->[1]++;
				if ($t > $r->[2]) {
					$r->[2] = $t;
					$r->[3] = $by;
				}
				$changed++;
			} else {
				$r = [$tok, 1, $t, $by];
				unshift @{$self->[1]}, $r;
				$changed++;
			}
		}
	}
	$self->put if $changed;
}

sub get
{
	return undef unless $dbm;
	my $key = uc shift;
	my $value;
	
	my $r = $dbm->get($key, $value);
	return undef if $r;
	return thaw($value);
}

sub put
{
	return unless $dbm;
	my $self = shift;
	my $key = $self->[0];
	my $value = nfreeze($self);
	$dbm->put($key, $value);
}

1;
