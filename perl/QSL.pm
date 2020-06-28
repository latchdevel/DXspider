#!/usr/bin/perl -w
#
# Local 'autoqsl' module for DXSpider
#
# Copyright (c) 2003 Dirk Koopman G1TLH
#

package QSL;

use strict;
use SysVar;
use DXUtil;
use DB_File;
use DXDebug;
use Prefix;
use JSON;
use Data::Structure::Util qw(unbless);

use vars qw($qslfn $dbm $maxentries);
$qslfn = 'dxqsl';
$dbm = undef;
$maxentries = 50;

my $json;

localdata_mv("$qslfn.v1j");

sub init
{
	my $mode = shift;
	my $ufn = localdata("$qslfn.v1j");

	$json = JSON->new->canonical(1);
	
	Prefix::load() unless Prefix::loaded();
	

	my %u;
	undef $dbm;
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

# called $self->update(comment, time, spotter)
# $self has the callsign as the first argument in an array of array references
# the format of each entry is [manager, times found, last time, last reporter]
sub update
{
	return unless $dbm;
	my $self = shift;
	my $line = shift;
	my $t = shift;
	my $by = shift;
	my $changed;

	return unless length $line && $line =~ /\b(?:QSL|VIA)\b/i;
	foreach my $man (split /\b/, uc $line) {
		my $tok;
		
		if (is_callsign($man) && !is_qra($man)) {
			my @pre = Prefix::extract($man);
			$tok = $man if @pre && $pre[0] ne 'Q';
		} elsif ($man =~ /^BUR/) {
			$tok = 'BUREAU';
		} elsif ($man =~ /^LOTW/) {
			$tok = 'LOTW';
		} elsif ($man eq 'HC' || $man =~ /^HOM/ || $man =~ /^DIR/) {
			$tok = 'HOME CALL';
		} elsif ($man =~ /^QRZ/) {
			$tok = 'QRZ.com';
		} else {
			next;
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
			# prune the number of entries
			pop @{$self->[1]} while (@{$self->[1]} > $maxentries);
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
	return decode($value);
}

sub put
{
	return unless $dbm;
	my $self = shift;
	my $key = $self->[0];
	my $value = encode($self);
	$dbm->put($key, $value);
}

sub remove_files
{
	unlink "$main::data/qsl.v1j";
	unlink "$main::local_data/qsl.v1j";
}

# thaw the user
sub decode
{
    my $s = shift;
    my $ref;
    eval { $ref = $json->decode($s) };
    if ($ref && !$@) {
        return bless $ref, 'QSL';
    } 
    return undef;
}

# freeze the user
sub encode
{
    my $ref = shift;
    unbless($ref);
    my $s;
	
	eval {$s = $json->encode($ref) };
	if ($s && !$@) {
		bless $ref, 'QSL';
		return $s;
	} 
}

1;
