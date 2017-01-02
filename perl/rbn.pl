#!/usr/bin/perl
#
# An RBN deduping filter
#
# Copyright (c) 2017 Dirk Koopman G1TLH
#

use strict;
use 5.10.1;
use IO::Socket::IP -register;
use Math::Round qw(nearest);

my $host = 'telnet.reversebeacon.net';
my $port = 7000;
my $mycall = shift or die "usage:rbn.pl <callsign> [debug] [stats] [cw] [rtty] [psk] [beacon] [<time between repeat spots in minutes>]\n"; 

my $minspottime = 30*60;		# minimum length of time between successive spots
my $showstats;					# show RBN and Spot stats

my $attempts;
my $sock;
my $dbg;
my $wantcw = 1;
my $wantrtty = 1;
my $wantpsk = 1;
my $wantbeacon = 1;
my $override; 
	
while (@ARGV) {
	my $arg = shift;

	++$dbg if $arg =~ /^deb/i;
	++$showstats if $arg =~ /^stat/i;
	$minspottime = $arg * 60 if $arg =~ /^\d+$/;
	if (!$override && $arg =~ /^cw|rtty|psk|beacon$/i) {
		$override = 1;
		$wantcw = $wantrtty = $wantpsk = $wantbeacon = 0;
	}
	++$wantcw if $arg =~ /^cw$/i;
	++$wantpsk if $arg =~ /^psk$/i;
	++$wantrtty if $arg =~ /^rtty$/i;
	++$wantbeacon if $arg =~ /^beacon$/i;
}

for ($attempts = 1; $attempts <= 5; ++$attempts) {
	say "admin,connecting to $host $port.. (attempt $attempts) " if $dbg;
	$sock = IO::Socket::IP->new(
								PeerHost => $host,
								PeerPort => $port,
								Timeout => 2,
							   );
	last if $sock;
}

die "admin,Cannot connect to $host:$port after 5 attempts $!" unless $sock;
say "admin,connected" if $dbg;
print $sock "$mycall\r\n";
say "admin,call sent" if $dbg;

my %d;
my %spot;

my $last = 0;
my $noraw = 0;
my $norbn = 0;
my $nospot = 0;

while (<$sock>) {
	chomp;
	my $tim = time;
	
	# periodic clearing out of the two caches
	if ($tim % 60 == 0 && $last != $tim) {
		my $count = 0;
		my $removed = 0;
		
		while (my ($k,$v) = each %d) {
			if ($tim-$v > 60) {
				delete $d{$k};
				++$removed
			} else {
				++$count;
			}
		}
		say "admin,rbn cache: $removed removed $count remain" if $dbg;
		$count = $removed = 0;
		while (my ($k,$v) = each %spot) {
			if ($tim-$v > $minspottime*2) {
				delete $spot{$k};
				++$removed;
			} else {
				++$count;
			}
		}
		say "admin,spot cache: $removed removed $count remain" if $dbg;

		say join(',', "STAT", $noraw, $norbn, $nospot) if $showstats;
		$noraw = $norbn = $nospot = 0;

		$last = $tim;
	}

	# parse line
	my (undef, undef, $origin, $qrg, $call, $mode, $s, $m, $spd, $u, $sort, $t) = split /[:\s]+/;
	if ($t) {

		# We have an RBN data line, dedupe it very simply on time, ignore QRG completely.
		# This works because the skimmers are NTP controlled (or should be) and will receive
		# the spot at the same time (velocity factor of the atmosphere taken into account :-)
		my $p = "$t|$call";
		++$noraw;
		next if $d{$p};

		# new RBN input
		$d{$p} = $tim;
		++$norbn;
		$qrg = sprintf('%.1f', nearest(.1, $qrg));     # to nearest 100Hz (to catch the odd multiple decpl QRG [eg '7002.07']).
		say join(',', "RBN", $origin, $qrg, $call, $mode, $s, $m, $spd, $u, $sort, $t) if $dbg;

		# Determine whether to "SPOT" it based on whether we have not seen it before (near this QRG) or,
		# if we have, has it been a "while" since the last time we spotted it? If it has been spotted
		# before then "RESPOT" it.
		my $nqrg = nearest(1, $qrg);  # normalised to nearest Khz
		my $sp = "$call|$nqrg";		  # hopefully the skimmers will be calibrated at least this well! 
		my $ts = $spot{$sp};
		
		if (!$ts || $tim - $ts >= $minspottime) {
			if ($wantbeacon && $sort =~ /^BEA/) {
				;
			} else {
				next if !$wantcw  && $mode =~ /^CW/;
				next if !$wantrtty && $mode =~ /^RTTY/;
				next if !$wantpsk && $mode =~ /^PSK/;
			}

			++$nospot;
			my $tag = $ts ? "RESPOT" : "SPOT";
			say join(',', $tag, $origin, $qrg, $call, $mode, $s, $m, $spd, $u, $sort, $t);
			$spot{$sp} = $tim;
		}
	} else {
		say "data,$_" if $dbg;
	}
}


close $sock;
exit 0;
