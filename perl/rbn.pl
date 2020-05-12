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
use Getopt::Long;
use Pod::Usage;

my $host = 'telnet.reversebeacon.net';
my $port = 7000;

my $minspottime = 60*60;		# minimum length of time between successive identical spots
my $showstats;					# show RBN and Spot stats

my $attempts;
my $sock;
my $dbg;
my $wantcw = 1;
my $wantrtty = 1;
my $wantpsk = 1;
my $wantbeacon = 1;
my $wantdx = 1;
my $wantft = 1;
my $wantpsk = 1;
my $wantraw = 0;
my $showrbn;
my $help = 0;
my $man = 0;
my $mycall;

#Getopt::Long::Configure( qw(auto_abbrev) );
GetOptions('host=s' => \$host,
		   'port=i' => \$port,
		   'debug' => \$dbg,
		   'rbn' => \$showrbn,
		   'stats' => \$showstats,
		   'raw' => \$wantraw,
		   'repeattime|rt=i' => sub { $minspottime = $_[1] * 60 },
		   'want=s' => sub {
			   my ($name, $value) = @_;
			   $wantcw = $wantrtty = $wantpsk = $wantbeacon = $wantdx = $wantft = $wantpsk = 0;
			   for (split /[:,\|]/, $value) {
				   ++$wantcw if /^cw$/i;
				   ++$wantpsk if /^psk$/i;
				   ++$wantrtty if /^rtty$/i;
				   ++$wantbeacon if /^beacon/i;
				   ++$wantdx if /^dx$/i;
				   ++$wantft if /^ft$/;
				   ++$wantft, ++$wantrtty, ++$wantpsk if /^digi/;
			   }
		   },
		   'help|?' => \$help,
		   'man' => \$man,
		   '<>' => sub { $mycall = shift },
		  ) or pod2usage(2);

$mycall ||= shift;

pod2usage(1) if $help || !$mycall;
pod2usage(-exitval => 0, -verbose => 2) if $man;


for ($attempts = 1; $attempts <= 5; ++$attempts) {
	say "ADMIN,connecting to $host $port.. (attempt $attempts) " if $dbg;
	$sock = IO::Socket::IP->new(
								PeerHost => $host,
								PeerPort => $port,
								Timeout => 2,
							   );
	last if $sock;
}

die "ADMIN,Cannot connect to $host:$port after 5 attempts $!\n" unless $sock;
say "ADMIN,connected" if $dbg;
$sock->timeout(0);

print $sock "$mycall\r\n";
say "ADMIN,call $mycall sent" if $dbg;

my %d;
my %spot;

my $last = 0;
my $noraw = 0;
my $norbn = 0;
my $nospot = 0;

while (<$sock>) {
	chomp;
	my $tim = time;

	# parse line
	say "RAW,$_" if $wantraw;

	if (/call:/) {
		print $sock "$mycall\r\n";
		say "ADMIN,call $mycall sent" if $dbg;
	}

	my (undef, undef, $origin, $qrg, $call, $mode, $s, $m, $spd, $u, $sort, $t, $tx) = split /[:\s]+/;
	my $b;
	
	if ($t || $tx) {

		# fix up times for things like 'NXDXF B' etc
		if ($tx && $t !~ /^\d{4}Z$/) {
			if ($tx =~ /^\d{4}Z$/) {
				$b = $t;
				$t = $tx;
			} else {
				say "ERR,$_";
				next;
			}
		}

		# We have an RBN data line, dedupe it very simply on time, ignore QRG completely.
		# This works because the skimmers are NTP controlled (or should be) and will receive
		# the spot at the same time (velocity factor of the atmosphere and network delays
		# carefully (not) taken into account :-)

		# Note, there is no intelligence here, but there are clearly basic heuristics that could
		# be applied at this point that reject (more likely rewrite) the call of a busted spot that would
		# useful for a zonal hotspot requirement from the cluster node.

		# In reality, this mechanism would be incorporated within the cluster code, utilising the dxqsl database,
		# and other resources in DXSpider, thus creating a zone map for an emitted spot. This is then passed through the
		# normal "to-user" spot system (where normal spots are sent to be displayed per user) and then be
		# processed through the normal, per user, spot filtering system - like a regular spot.

		# The key to this is deducing the true callsign by "majority voting" (the greater the number of spotters
        # the more effective this is) together with some lexical analsys probably in conjuction with DXSpider
		# data sources (for singleton spots) to then generate a "centre" from and to zone (whatever that will mean if it isn't the usual one)
		# and some heuristical "Kwalitee" rating given distance from the zone centres of spotter, recipient user
        # and spotted. A map can be generated once per user and spotter as they are essentially mostly static. 
		# The spotted will only get a coarse position unless other info is available. Programs that parse 
		# DX bulletins and the online data online databases could be be used and then cached. 

		# Obviously users have to opt in to receiving RBN spots and other users will simply be passed over and
		# ignored.

		# Clearly this will only work in the 'mojo' branch of DXSpider where it is possible to pass off external
		# data requests to ephemeral or semi resident forked processes that do any grunt work and the main
		# process to just the standard "message passing" which has been shown to be able to sustain over 5000 
		# per second (limited by the test program's output and network speed, rather than DXSpider's handling).  
		
		my $p = "$t|$call";
		++$noraw;
		next if $d{$p};

		# new RBN input
		$d{$p} = $tim;
		++$norbn;
		$qrg = sprintf('%.1f', nearest(.1, $qrg));     # to nearest 100Hz (to catch the odd multiple decpl QRG [eg '7002.07']).
		if (!$wantraw && ($dbg || $showrbn)) {
			my $s = join(',', "RBN", $origin, $qrg, $call, $mode, $s, $m, $spd, $u, $sort, $t);
			$s .= ",$b" if $b;
			say $s;
		}

		# Determine whether to "SPOT" it based on whether we have not seen it before (near this QRG) or,
		# if we have, has it been a "while" since the last time we spotted it? If it has been spotted
		# before then "RESPOT" it.
		my $nqrg = nearest(1, $qrg);  # normalised to nearest Khz
		my $sp = "$call|$nqrg";		  # hopefully the skimmers will be calibrated at least this well! 
		my $ts = $spot{$sp};

		if (!$ts || ($minspottime > 0 && $tim - $ts >= $minspottime)) {
			my $want;

			++$want if $wantbeacon && $sort =~ /^BEA|NCD/;
			++$want if $wantcw && $mode =~ /^CW/;
			++$want if $wantrtty && $mode =~ /^RTTY/;
			++$want if $wantpsk && $mode =~ /^PSK/;
			++$want if $wantdx && $mode =~ /^DX/;
			++$want if $wantft && $mode =~ /^FT/;
			if ($want) {
				++$nospot;
				my $tag = $ts ? "RESPOT" : "SPOT";
				$t .= ",$b" if $b;
				say join(',', $tag, $origin, $qrg, $call, $mode, $s, $m, $spd, $u, $sort, $t);
				$spot{$sp} = $tim;
			}
		}
	} else {
		say "DATA,$_" if $dbg && !$wantraw;
	}

	# periodic clearing out of the two caches
	if (($tim % 60 == 0 && $tim > $last) || ($last && $tim >= $last + 60)) {
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
		say "ADMIN,rbn cache: $removed removed $count remain" if $dbg;
		$count = $removed = 0;
		while (my ($k,$v) = each %spot) {
			if ($tim-$v > $minspottime*2) {
				delete $spot{$k};
				++$removed;
			} else {
				++$count;
			}
		}
		say "ADMIN,spot cache: $removed removed $count remain" if $dbg;

		say join(',', "STAT", $noraw, $norbn, $nospot) if $showstats;
		$noraw = $norbn = $nospot = 0;

		$last = int($tim / 60) * 60;
	}
}


close $sock;
exit 0;

__END__

=head1 NAME

rbn.pl - an experimental RBN filter program 

=head1 SYNOPSIS

rbn.pl [options] <any callsign>

We read the raw data
from the RBN. We collect similar spots on a frequency within 100hz and try to
deduce which if them is likely to be the true callsign. Emitted spots are cached and thereafter ignored
for a period until it is spotted again, when it may be emitted again - but marked as a RESPOT. 

This is just technology demonstrator designed to scope out the issues and make sure that the line decoding works
in all circumstances. But even on busy weekends it seems to cope just fine deduping away within its limits.

To see it work at its best, run it as: rbn.pl -stats <any callsign>

Leave it running for some time, preferably several (10s of) minutes.
You will see it slowly reduce the number of new spots until you start to see "RESPOT" lines. Reductions
of more than one order of magnitude is normal. Particularly when there are many more spotters. 

=head1 OPTIONS

=over 8

=item B<-help>

Print a brief help message and exits.

=item B<-man>

Prints the manual page and exits.

=item B<-host>=telnet.reversebeacon.net 

As default, this program will connect to C<telnet.reversebeacon.net>. Use this argument to change that.

=item B<-port>=7000

As default, this program will connect to port 7000. Use this argument to change that to some other port.

=item B<-want>=cw,rtty,dx,beacon,psk,ft,digital

The program will print all spots in all classes in the 'mode/calling' column [cw, rtty, beacon, dx, psk, ft, digital]. You can choose one or more of
these classes if you want specific types of spots. The class 'digital' is equivalent to [rtty,psk,ft]. The class 'beacon' includes
NCDXF beacons. 

E.g. rbn.pl -want=psk,ft,beacon g9tst

=item B<-stats>

Print a comma separated line of statistics once a minute which consists of:

STAT,E<lt>raw RBN spotsE<gt>,E<lt>de-duped RBN spotsE<gt>,E<lt>new spotsE<gt>

=item B<-repeattime=60>

A cache of callsigns and QRGs is kept. If a SPOT comes in after B<repeattime> minutes then it re-emitted
but with a RESPOT tag instead. Set this argument to 0 (or less) if you do not want any repeats. 

=item B<-rbn>

Show the de-duplicated RBN lines as they come in.

=item B<-raw>

Show the raw RBN lines as they come in.

=back

=head1 DESCRIPTION

B<This program> connects (as default) to RBN C<telnet.reversebeacon.net:7000> and parses the raw output
which it deduplicates and then outputs unique spots. It is possible to select one or more types of spot. 

The output is the RBN spot line which has been separated out into a comma separated list. One line per spot.

Like this:

  SPOT,DK3UA-#,3560.0,DL6ZB,CW,27,dB,26,WPM,CQ,2152Z
  SPOT,WB6BEE-#,14063.0,KD6SX,CW,24,dB,15,WPM,CQ,2152Z
  RESPOT,S50ARX-#,1811.5,OM0CS,CW,37,dB,19,WPM,CQ,2152Z
  SPOT,DF4UE-#,3505.0,TA1PT,CW,11,dB,23,WPM,CQ,2152Z
  SPOT,AA4VV-#,14031.0,TF3Y,CW,16,dB,22,WPM,CQ,2152Z
  SPOT,SK3W-#,3600.0,OK0EN,CW,13,dB,11,WPM,BEACON,2152Z
  STAT,263,64,27

If the -raw flag is set then these lines will be interspersed with the raw line from the RBN source, prefixed 
with "RAW,". For example:

  RAW,DX de PJ2A-#:    14025.4  IP0TRC         CW    16 dB  31 WPM  CQ      1307Z
  RAW,DX de PJ2A-#:    10118.9  K1JD           CW     2 dB  28 WPM  CQ      1307Z
  RAW,DX de K2PO-#:     1823.4  HL5IV          CW     8 dB  22 WPM  CQ      1307Z
  SPOT,K2PO-#,1823.4,HL5IV,CW,8,dB,22,WPM,CQ,1307Z
  RAW,DX de LZ7AA-#:   14036.6  HA8GZ          CW     7 dB  27 WPM  CQ      1307Z
  RAW,DX de DF4UE-#:   14012.0  R7KM           CW    32 dB  33 WPM  CQ      1307Z
  RAW,DX de G7SOZ-#:   14012.2  R7KM           CW    17 dB  31 WPM  CQ      1307Z


=cut

