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

use vars qw($VERSION $BRANCH);
$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /\d+\.\d+\.(\d+)\.(\d+)/  || (0,0));
$main::build += $VERSION;
$main::branch += $BRANCH;

use vars qw($qslfn $dbm);
$qslfn = 'qsl';
$dbm = undef;

sub init
{
	my $mode = shift;
	my $ufn = "$main::root/data/$qslfn.v1";

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

# the format of each entry is [manager, times found, last time]
sub update
{
	return unless $dbm;
	my $self = shift;
	my $line = shift;
	my $t = shift;
	my $by = shift;
		
	my @tok = map {/^(?:HC|BUR|QRZ|HOME)/ || is_callsign($_) ? $_ : ()} split(/\b/, uc $line);
	foreach my $man (@tok) {
		if ($man =~ /^BUR/) {
			$man = 'BUREAU';
		} elsif ($man eq 'HC' || $man =~ /^HOM/) {
			$man = 'HOME CALL';
		} elsif ($man =~ /^QRZ/) {
			$man = 'QRZ.com';
		}
		my ($r) = grep {$_->[0] eq $man} @{$self->[1]};
		if ($r) {
			$r->[1]++;
			if ($t > $r->[2]) {
				$r->[2] = $t;
				$r->[3] = $by;
			}
		} else {
			$r = [$man, 1, $t, $by];
			unshift @{$self->[1]}, $r;
		}
	}
	$self->put;
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
