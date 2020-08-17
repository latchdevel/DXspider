#
# The RBN connection system
#
# Copyright (c) 2020 Dirk Koopman G1TLH
#

use warnings;
use strict;

package RBN;

use 5.10.1;

use lib qw {.};

use DXDebug;
use DXUtil;
use DXLog;
use DXUser;
use DXChannel;
use Math::Round qw(nearest nearest_floor);
use Date::Parse;
use Time::HiRes qw(gettimeofday);
use Spot;
use DXJSON;
use IO::File;

use constant {
			  ROrigin => 0,
			  RQrg => 1,
			  RCall => 2,
			  RMode => 3,
			  RStrength => 4,
			  RTime => 5,
			  RUtz => 6,
			  Respot => 7,
			  RQra => 8,
			  RSpotData => 9,
			 };

use constant {
			  SQrg => 0,
			  SCall => 1,
			  STime => 2,
			  SComment => 3,
			  SOrigin => 4,
			  SZone => 11,
			 };
use constant {
			  OQual => 0,
			  OAvediff => 1,
			  OSpare => 2,
			  ODiff => 3,
			 };
use constant {
			  CTime => 0,
			  CQual => 1,
			  CData => 2,
			 };

use constant {
			  DScore => 0,
			  DGood => 1,
			  DBad => 2,
			  DLastin => 3,
			  DEviants => 4,
			 };


our $DATA_VERSION = 1;

our @ISA = qw(DXChannel);

our $startup_delay = 5*60;		# don't send anything out until this timer has expired
                                # this is to allow the feed to "warm up" with duplicates
                                # so that the "big rush" doesn't happen.

our $minspottime = 30*60;		# the time between respots of a callsign - if a call is
                                # still being spotted (on the same freq) and it has been
                                # spotted before, it's spotted again after this time
                                # until the next minspottime has passed.

our $beacontime = 5*60;			# same as minspottime, but for beacons (and shorter)

our $dwelltime = 10; 			# the amount of time to wait for duplicates before issuing
                                # a spot to the user (no doubt waiting with bated breath).

our $filterdef = $Spot::filterdef; # we use the same filter as the Spot system. Can't think why :-).

my $spots;						# the GLOBAL spot cache

my %runtime;					# how long each channel has been running

our $cachefn = localdata('rbn_cache');
our $cache_valid = 4*60;		# The cache file is considered valid if it is not more than this old

our $maxqrgdiff = 10;			# the maximum
our $minqual = 2;				# the minimum quality we will accept for output

my $json;
my $noinrush = 0;				# override the inrushpreventor if set
our $maxdeviants = 5;			# the number of deviant QRGs to record for skimmer records

sub init
{
	$json = DXJSON->new;
	$json->canonical(0);
	if (check_cache()) {
		$noinrush = 1;
	} else {
		$spots = {VERSION=>$DATA_VERSION};
	}
	if (defined $DB::VERSION) {
		$noinrush = 1;
		$json->indent(1);
	}
	
}

sub new 
{
	my $self = DXChannel::alloc(@_);

	# routing, this must go out here to prevent race condx
	my $pkg = shift;
	my $call = shift;

	$self->{last} = 0;
	$self->{noraw} = 0;
	$self->{nospot} = 0;
	$self->{nouser} = {};
	$self->{norbn} = 0;
	$self->{noraw10} = 0;
	$self->{nospot10} = 0;
	$self->{nouser10} = {};
	$self->{norbn10} = 0;
	$self->{nospothour} = 0;
	$self->{nouserhour} = {};
	$self->{norbnhour} = 0;
	$self->{norawhour} = 0;
	$self->{sort} = 'N';
	$self->{lasttime} = $main::systime;
	$self->{minspottime} = $minspottime;
	$self->{beacontime} = $beacontime;
	$self->{showstats} = 0;
	$self->{pingint} = 0;
	$self->{nopings} = 0;
	$self->{queue} = {};

	return $self;
}

sub start
{ 
	my ($self, $line, $sort) = @_;
	my $user = $self->{user};
	my $call = $self->{call};
	my $name = $user->{name};
		
	# log it
	my $host = $self->{conn}->peerhost;
	$host ||= "unknown";
	$self->{hostname} = $host;

	$self->{name} = $name ? $name : $call;
	$self->state('prompt');		# a bit of room for further expansion, passwords etc
	$self->{lang} = $user->lang || $main::lang || 'en';
	if ($line =~ /host=/) {
		my ($h) = $line =~ /host=(\d+\.\d+\.\d+\.\d+)/;
		$line =~ s/\s*host=\d+\.\d+\.\d+\.\d+// if $h;
		unless ($h) {
			($h) = $line =~ /host=([\da..fA..F:]+)/;
			$line =~ s/\s*host=[\da..fA..F:]+// if $h;
		}
		if ($h) {
			$h =~ s/^::ffff://;
			$self->{hostname} = $h;
		}
	}
	$self->{width} = 80 unless $self->{width} && $self->{width} > 80;
	$self->{consort} = $line;	# save the connection type

	LogDbg('DXCommand', "$call connected from $self->{hostname}");

	# set some necessary flags on the user if they are connecting
	$self->{registered} = 1;
	# sort out privilege reduction
	$self->{priv} = 0;

	# get the filters
	my $nossid = $call;
	$nossid =~ s/-\d+$//;

	$self->{inrbnfilter} = Filter::read_in('rbn', $call, 1) 
		|| Filter::read_in('rbn', 'node_default', 1);
	
	# clean up qra locators
	my $qra = $user->qra;
	$qra = undef if ($qra && !DXBearing::is_qra($qra));
	unless ($qra) {
		my $lat = $user->lat;
		my $long = $user->long;
		$user->qra(DXBearing::lltoqra($lat, $long)) if (defined $lat && defined $long);  
	}

	# if we have been running and stopped for a while 
	# if the cache is warm enough don't operate the inrush preventor
	$self->{inrushpreventor} = exists $runtime{$call} && $runtime{$call} > $startup_delay || $noinrush ?  0 : $main::systime + $startup_delay;
	dbg("RBN: noinrush: $noinrush, setting inrushpreventor on $self->{call} to $self->{inrushpreventor}");
}

my @queue;						# the queue of spots ready to send

sub normal
{
	my $self = shift;
	my $line = shift;
	my @ans;
	my $dbgrbn = isdbg('rbn');
	
	# remove leading and trailing spaces
	chomp $line;
	$line =~ s/^\s*//;
	$line =~ s/\s*$//;

	# add base RBN

	my $now = $main::systime;

	# parse line
	dbg "RBN:RAW,$line" if isdbg('rbnraw');
	return unless $line=~/^DX\s+de/;

	my (undef, undef, $origin, $qrg, $call, $mode, $s, $m, $spd, $u, $sort, $t, $tx) = split /[:\s]+/, $line;

	# fix up FT8 spots from 7001
	$t = $u, $u = '' if !$t && is_ztime($u);
	$t = $sort, $sort = '' if !$t && is_ztime($sort);
	my $qra = $spd, $spd = '' if is_qra($spd);
	$u = $qra if $qra;

	# is this anything like a callsign?
	unless (is_callsign($call)) {
		dbg("RBN: ERROR $call from $origin on $qrg is invalid, dumped");
		return;
	}

	$origin =~ s/\-(?:\d{1,2}\-)?\#$//; # get rid of all the crap we aren't interested in


	$sort ||= '';
	$tx ||= '';
	$qra ||= '';
    dbg qq{RBN:input decode or:$origin qr:$qrg ca:$call mo:$mode s:$s m:$m sp:$spd u:$u sort:$sort t:$t tx:$tx qra:$qra} if $dbgrbn;

	++$self->{noraw};
	++$self->{noraw10};
	++$self->{norawhour};
	
	my $b;
	
	if ($t || $tx) {

		# fix up times for things like 'NXDXF B' etc
		if ($tx && is_ztime($t)) {
			if (is_ztime($tx)) {
				$b = $t;
				$t = $tx;
			} else {
				dbg "RBN:ERR,$line";
				return (0);
			}
		}
		if ($sort && $sort eq 'NCDXF') {
			$mode = 'DXF';
			$t = $tx;
		}
		if ($sort && $sort eq 'BEACON') {
			$mode = 'BCN';
		}
		if ($mode =~ /^PSK/) {
			$mode = 'PSK';
		}
		if ($mode eq 'RTTY') {
			$mode = 'RTT';
		}

		# The main de-duping key is [call, $frequency], but we probe a bit around that frequency to find a
		# range of concurrent frequencies that might be in play. 

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

		my $search = 5;
		my $nqrg = nearest(1, $qrg * 10);  # normalised to nearest Khz
		my $sp = "$call|$nqrg";		  # hopefully the skimmers will be calibrated at least this well!

		# find it?
		my $cand = $spots->{$sp};
		unless ($cand) {
			my ($i, $new);
			for ($i = $nqrg; !$cand && $i <= $nqrg+$search; $i += 1) {
				$new = "$call|$i";
				$cand = $spots->{$new}, last if exists $spots->{$new};
			}
			if ($cand) {
				my $diff = $i - $nqrg;
				dbg(qq{RBN: QRG Diff using $new (+$diff) for $sp for qrg $qrg}) if (isdbg('rbnqrg') || $dbgrbn);
				$sp = $new;
			}
		}
		unless ($cand) {
			my ($i, $new);
			for ($i = $nqrg; !$cand && $i >= $nqrg-$search; $i -= 1) {
				$new = "$call|$i";
				$cand = $spots->{$new}, last if exists $spots->{$new};
			}
			if ($cand) {
				my $diff = $nqrg - $i;
				dbg(qq{RBN: QRG Diff using $new (-$diff) for $sp for qrg $qrg}) if (isdbg('rbnqrg') || $dbgrbn);
				$sp = $new;
			}
		}
		
		# if we have one and there is only one slot and that slot's time isn't expired for respot then return
		my $respot = 0;
		if ($cand && ref $cand) {
			if (@$cand <= CData) {
				unless ($self->{minspottime} > 0 && $now - $cand->[CTime] >= $self->{minspottime}) {
					dbg("RBN: key: '$sp' call: $call qrg: $qrg DUPE \@ ". atime(int $cand->[CTime])) if $dbgrbn;
					return;
				}
				
				dbg("RBN: key: '$sp' RESPOTTING call: $call qrg: $qrg last seen \@ ". atime(int $cand->[CTime])) if $dbgrbn;
				$cand->[CTime] = $now;
				++$respot;
			}

			# otherwise we have a spot being built up at the moment
		} elsif ($cand) {
			dbg("RBN: key '$sp' = '$cand' not ref");
			return;
		}

		# here we either have an existing spot record buildup on the go, or we need to create the first one
		unless ($cand) {
			$spots->{$sp} = $cand = [$now, 0];
			dbg("RBN: key: '$sp' call: $call qrg: $qrg NEW" . ($respot ? ' RESPOT' : '')) if $dbgrbn;
		}

		# add me to the display queue unless we are waiting for initial in rush to finish
		return unless $noinrush || $self->{inrushpreventor} < $main::systime;

		# build up a new record and store it in the buildup
		# deal with the unix time
		my ($hh,$mm) = $t =~ /(\d\d)(\d\d)Z$/;
		my $utz = $hh*3600 + $mm*60 + $main::systime_daystart; # possible issue with late spot from previous day
		$utz -= 86400 if $utz > $now+3600;					   # too far ahead, drag it back one day

		# create record and add into the buildup
		my $r = [$origin, nearest(.1, $qrg), $call, $mode, $s, $t, $utz, $respot, $u];
		my @s =  Spot::prepare($r->[RQrg], $r->[RCall], $r->[RUtz], '', $r->[ROrigin]);
		if ($s[5] == 666) {
			dbg("RBN: ERROR invalid prefix/callsign $call from $origin-# on $qrg, dumped");
			return;
		}
		
		if ($self->{inrbnfilter}) {
			my ($want, undef) = $self->{inrbnfilter}->it($s);
			return unless $want;	
		}
		$r->[RSpotData] = \@s;

		++$self->{queue}->{$sp};# unless @$cand>= CData; # queue the KEY (not the record)

		dbg("RBN: key: '$sp' ADD RECORD call: $call qrg: $qrg origin: $origin") if $dbgrbn;

		push @$cand, $r;

	} else {
		dbg "RBN:DATA,$line" if $dbgrbn;
	}
}

# we should get the spot record minus the time, so just an array of record (arrays)
sub send_dx_spot
{
	my $self = shift;
	my $quality = shift;
	my $cand = shift;

	++$self->{norbn};
	++$self->{norbn10};
	++$self->{norbnhour};
	
	# $r = [$origin, $qrg, $call, $mode, $s, $utz, $respot];

	my $mode = $cand->[CData]->[RMode]; # as all the modes will be the same;
	
	my @dxchan = DXChannel::get_all();

	foreach my $dxchan (@dxchan) {
		next unless $dxchan->is_user;
		my $user = $dxchan->{user};
		next unless $user &&  $user->wantrbn;

		# does this user want this sort of spot at all?
		my $want = 0;
		++$want if $user->wantbeacon && $mode =~ /^BCN|DXF/;
		++$want if $user->wantcw && $mode =~ /^CW/;
		++$want if $user->wantrtty && $mode =~ /^RTT/;
		++$want if $user->wantpsk && $mode =~ /^PSK|FSK|MSK/;
		++$want if $user->wantft && $mode =~ /^FT/;

		dbg(sprintf("RBN: spot selection for $dxchan->{call} mode: '$mode' want: $want flags rbn:%d ft:%d bcn:%d cw:%d psk:%d rtty:%d",
					$user->wantrbn,
					$user->wantft,
					$user->wantbeacon,
					$user->wantcw,
					$user->wantpsk,
					$user->wantrtty,
				   )) if isdbg('rbnll');

		# send one spot to one user out of the ones that we have
		$self->dx_spot($dxchan, $quality, $cand) if $want;
	}
}

sub dx_spot
{
	my $self = shift;
	my $dxchan = shift;
	my $quality = shift;
	my $cand = shift;
	my $call = $dxchan->{call};
	my $seeme = $dxchan->user->rbnseeme();
	my $strength = 100;		# because it could if we talk about FTx
	my $saver;
	my %zone;
	my $respot;
	my $qra;

	++$self->{nousers}->{$call};
	++$self->{nousers10}->{$call};
	++$self->{nousershour}->{$call};

	my $filtered;
	my $rf = $dxchan->{rbnfilter} || $dxchan->{spotsfilter};
	my $comment;
	
	foreach my $r (@$cand) {
		# $r = [$origin, $qrg, $call, $mode, $s, $t, $utz, $respot, $qra];
		# Spot::prepare($qrg, $call, $utz, $comment, $origin);
		next unless $r && ref $r;

		$qra = $r->[RQra] if !$qra && $r->[RQra] && is_qra($r->[RQra]);

		$comment = sprintf "%-3s %2ddB $quality", $r->[RMode], $r->[RStrength];
		my $s = $r->[RSpotData];		# the prepared spot
		$s->[SComment] = $comment;		# apply new generated comment

		++$zone{$s->[SZone]};		# save the spotter's zone

		# if the 'see me' flag is set, then show all the spots without further adornment (see set/rbnseeme for more info)
		if ($seeme) {
			send_final($dxchan, $s);
			next;
		}

		# save the lowest strength one
		if ($r->[RStrength] < $strength) {
			$strength = $r->[RStrength];
			$saver = $s;
			dbg("RBN: STRENGTH spot: $s->[SCall] qrg: $s->[SQrg] origin: $s->[SOrigin] dB: $r->[RStrength] < $strength") if isdbg 'rbnll';
		}

		if ($rf) {
			my ($want, undef) = $rf->it($s);
			dbg("RBN: FILTERING for $call spot: $s->[SCall] qrg: $s->[SQrg] origin: $s->[SOrigin] dB: $r->[RStrength] com: '$s->[SComment]' want: " . ($want ? 'YES':'NO')) if isdbg 'rbnll';
			next unless $want;
			$filtered = $s;
		}
	}

	if ($rf) {
		$saver = $filtered;		# if nothing passed the filter's lips then $saver == $filtered == undef !
	}
	
	if ($saver) {
		my $buf;
		# create a zone list of spotters
		delete $zone{$saver->[SZone]};  # remove this spotter's zone (leaving all the other zones)
		my $z = join ',', sort {$a <=> $b} keys %zone;

		# alter spot data accordingly
		$saver->[SComment] .= " Z:$z" if $z;
		
		send_final($dxchan, $saver);
		
		++$self->{nospot};
		++$self->{nospot10};
		++$self->{nospothour};
		
		if ($qra) {
			my $user = DXUser::get_current($saver->[SCall]) || DXUser->new($saver->[SCall]);
			unless ($user->qra && is_qra($user->qra)) {
				$user->qra($qra);
				dbg("RBN: update qra on $saver->[SCall] to $qra");
				$user->put;
			}
		}
	}
}

sub send_final
{
	my $dxchan = shift;
	my $saver = shift;
	my $call = $dxchan->{call};
	my $buf;
	
	dbg("RBN: SENDING to $call spot: $saver->[SCall] qrg: $saver->[SQrg] origin: $saver->[SOrigin] $saver->[SComment]") if isdbg 'rbnll';
	if ($dxchan->{ve7cc}) {
		my $call = $saver->[SOrigin];
		$saver->[SOrigin] .= '-#';
		$buf = VE7CC::dx_spot($dxchan, @$saver);
		$saver->[SOrigin] = $call;
	} else {
		my $call = $saver->[SOrigin];
		$saver->[SOrigin] = substr($call, 0, 6);
		$saver->[SOrigin] .= '-#';
		$buf = $dxchan->format_dx_spot(@$saver);
		$saver->[SOrigin] = $call;
	}
	$dxchan->local_send('N', $buf);
}

# per second
sub process
{
	my $rbnskim = isdbg('rbnskim');
	
	foreach my $dxchan (DXChannel::get_all()) {
		next unless $dxchan->is_rbn;

		# At this point we run the queue to see if anything can be sent onwards to the punter
		my $now = $main::systime;
		my $ta = [gettimeofday];
		my $items = 0;
		
		# now run the waiting queue which just contains KEYS ($call|$qrg)
		foreach my $sp (keys %{$dxchan->{queue}}) {
			my $cand = $spots->{$sp};
			++$items;
			unless ($cand && $cand->[CTime]) {
				dbg "RBN Cand $sp " . ($cand ? 'def' : 'undef') . " [CTime] " . ($cand->[CTime] ? 'def' : 'undef') . " dwell $dwelltime";
				next;
			} 
			if ($now >= $cand->[CTime] + $dwelltime ) {
				# we have a candidate, create qualitee value(s);
				unless (@$cand > CData) {
					dbg "RBN: QUEUE key '$sp' MISSING RECORDS, IGNORED" . dd($cand) if isdbg 'rbnqueue';
					delete $spots->{$sp}; # don't remember it either - this means that a spot HAS to come in with sufficient spotters to be processed.
					delete $dxchan->{queue}->{$sp};
					next;
				}
				dbg "RBN: QUEUE PROCESSING key: '$sp' $now >= $cand->[CTime]" if isdbg 'rbnqueue'; 
				my $quality = @$cand - CData;
				my $spotters = $quality;

				# dump it and remove it from the queue if it is of unadequate quality
				if ($quality < $minqual) {
					if ($rbnskim) {
						my $r = $cand->[CData];
						if ($r) {
							my $s = "RBN:SKIM Ignored (Q:$quality < Q:$minqual) key: '$sp' = $r->[RCall] on $r->[RQrg] by $r->[ROrigin] \@ $r->[RTime] route: $dxchan->{call}";
							dbg($s);
						}
					}
					delete $spots->{$sp}; # don't remember it either - this means that a spot HAS to come in with sufficient spotters to be processed.
					delete $dxchan->{queue}->{$sp};
					next;
				}

				$quality = 9 if $quality > 9;
				$cand->[CQual] = $quality if $quality > $cand->[CQual];

				my $r;

				# this scores each candidate according to its skimmer's QRG score (i.e. how often it agrees with its peers)
				# what happens is hash of all QRGs in candidates are incremented by that skimmer's reputation for "accuracy"
				# or, more exactly, past agreement with the consensus. This score can be from -5 -> +5. 
				my %qrg = ();
				my $skimmer;
				my $sk;
				my $band;
				my %seen = ();
				foreach $r (@$cand) {
					next unless ref $r;
					if (exists $seen{$r->[ROrigin]}) {
						undef $r;
						next;
					}
					$seen{$r->[ROrigin]} = 1;
					$band ||= int $r->[RQrg] / 1000;
					$sk = "SKIM|$r->[ROrigin]|$band"; # thus only once per set of candidates
					$skimmer = $spots->{$sk};
					unless ($skimmer) {
						$skimmer = $spots->{$sk} = [1, 0, 0, $now, []];	# this first time, this new skimmer gets the benefit of the doubt on frequency.
						dbg("RBN:SKIM new slot $sk " . $json->encode($skimmer)) if $rbnskim;
					}
					$qrg{$r->[RQrg]} += ($skimmer->[DScore] || 1);
				}
				
				# determine the most likely qrg and then set it - NOTE (-)ve votes, generated by the skimmer scoring system above, are ignored
				my @deviant;
				my $c = 0;
				my $mv = 0;
				my $qrg = 0;
				while (my ($k, $votes) = each %qrg) {
					if ($votes >= $mv) {
						$qrg = $k;
						$mv = $votes;
					}
					++$c;
				}

				# Ignore possible spots with 0 QRG score - as determined by the skimmer scoring system above -  as they are likely to be wrong 
				unless ($qrg > 0) {
					if ($rbnskim) {
						my $keys;
						while (my ($k, $v) = (each %qrg)) {
							$keys .= "$k=>$v, ";
						}
						$keys =~ /,\s*$/;
						my $i = 0;
						foreach $r (@$cand) {
							next unless $r && ref $r;
							dbg "RBN:SKIM cand $i QRG likely wrong from '$sp' = $r->[RCall] on $r->[RQrg] by $r->[ROrigin] \@ $r->[RTime] (qrgs: $keys c: $c) route: $dxchan->{call}, ignored";
							++$i;
						}
					}
					delete $spots->{$sp}; # get rid
					delete $dxchan->{queue}->{$sp};
					next;
				}

				# detemine and spit out the deviants. Then adjust the scores according to whether it is a deviant or good
				# NOTE: deviant nodes can become good (or less bad), and good nodes bad (or less good) on each spot that
				# they generate. This is based solely on each skimmer's agreement (or not) with the "consensus" score generated
				# above ($qrg). The resultant score + good + bad is stored per band and will be used the next time a spot
				# appears on this band from each skimmer.
				foreach $r (@$cand) {
					next unless $r && ref $r;
					my $diff = $c > 1 ? nearest(.1, $r->[RQrg] - $qrg) : 0;
					$sk = "SKIM|$r->[ROrigin]|$band";
					$skimmer = $spots->{$sk};
					if ($diff) {
						++$skimmer->[DBad] if $skimmer->[DBad] < $maxdeviants;
						--$skimmer->[DGood] if $skimmer->[DGood] > 0;
						push @deviant, sprintf("$r->[ROrigin]:%+.1f", $diff);
						push @{$skimmer->[DEviants]}, $diff;
						shift @{$skimmer->[DEviants]} while @{$skimmer->[DEviants]} > $maxdeviants;
					} else {
						++$skimmer->[DGood] if $skimmer->[DGood] < $maxdeviants;
						--$skimmer->[DBad] if $skimmer->[DBad] > 0;
						shift @{$skimmer->[DEviants]};
					}
					$skimmer->[DScore] = $skimmer->[DGood] - $skimmer->[DBad];
					my $lastin = difft($skimmer->[DLastin], $now, 2);
					my $difflist = join(', ', @{$skimmer->[DEviants]});
					$difflist = " ($difflist)" if $difflist;
					dbg("RBN:SKIM key $sp slot $sk $r->[RQrg] - $qrg = $diff Skimmer score: $skimmer->[DGood] - $skimmer->[DBad] = $skimmer->[DScore] lastseen:$lastin ago$difflist") if $rbnskim; 
					$skimmer->[DLastin] = $now;
					$r->[RSpotData]->[SQrg] = $qrg if $qrg && $c > 1; # set all the QRGs to the agreed value
				}

				$qrg = (sprintf "%.1f",  $qrg)+0;
				$r = $cand->[CData];
				$r->[RQrg] = $qrg;
				my $squality = "Q:$cand->[CQual]";
				$squality .= '*' if $c > 1; 
				$squality .= '+' if $r->[Respot];

				if (isdbg('progress')) {
					my $s = "RBN: SPOT key: '$sp' = $r->[RCall] on $r->[RQrg] by $r->[ROrigin] \@ $r->[RTime] $squality route: $dxchan->{call}";
					my $td = @deviant;
					$s .= " QRGScore $mv Deviants ($td/$spotters): ";
					$s .= join(', ', sort @deviant) if $td;
					dbg($s);
				}

				# finally send it out to any waiting public
				send_dx_spot($dxchan, $squality, $cand);
				
				# clear out the data and make this now just "spotted", but no further action required until respot time
				dbg "RBN: QUEUE key '$sp' cleared" if isdbg 'rbn';

				delete $dxchan->{queue}->{$sp};
				delete $spots->{$sp};

				# calculate new sp (which will be 70% likely the same as the old one)
				# we do this to cope with the fact that the first spotter may well be "wrongly calibrated" giving a qrg that disagrees with the majority.
				# and we want to store the key that corresponds to majority opinion. 
				my $nqrg = nearest(1, $qrg * 10);  # normalised to nearest Khz
				my $nsp = "$r->[RCall]|$nqrg";
				if ($sp ne $nsp) {
					dbg("RBN:SKIM CHANGE KEY sp '$sp' -> '$nsp' for storage") if $rbnskim;
					$spots->{$nsp} = [$now, $cand->[CQual]];
				}
			}
			else {
				dbg sprintf("RBN: QUEUE key: '$sp' SEND time not yet reached %.1f secs left", $cand->[CTime] + $dwelltime - $now) if isdbg 'rbnqueue'; 
			}
		}
		if (isdbg('rbntimer')) {
			my $diff = _diffus($ta);
			dbg "RBN: TIMER process queue for call: $dxchan->{call} $items spots $diff uS";
		}
	}
}

sub per_minute
{
	foreach my $dxchan (DXChannel::get_all()) {
		next unless $dxchan->is_rbn;
		dbg "RBN:STATS minute $dxchan->{call} raw: $dxchan->{noraw} retrieved spots: $dxchan->{norbn} delivered: $dxchan->{nospot} after filtering to users: " . scalar keys %{$dxchan->{nousers}} if isdbg('rbnstats');
		if ($dxchan->{noraw} == 0 && $dxchan->{lasttime} > 60) {
			LogDbg('RBN', "RBN: no input from $dxchan->{call}, disconnecting");
			$dxchan->disconnect;
		}
		$dxchan->{noraw} = $dxchan->{norbn} = $dxchan->{nospot} = 0; $dxchan->{nousers} = {};
		$runtime{$dxchan->{call}} += 60;
	}

	# save the spot cache
	write_cache() unless $main::systime + $startup_delay < $main::systime;;
}

sub per_10_minute
{
	my $count = 0;
	my $removed = 0;
	while (my ($k,$cand) = each %{$spots}) {
		next if $k eq 'VERSION';
		next if $k =~ /^O\|/;
		next if $k =~ /^SKIM\|/;
		
		if ($main::systime - $cand->[CTime] > $minspottime*2) {
			delete $spots->{$k};
			++$removed;
		}
		else {
			++$count;
		}
	}
	dbg "RBN:STATS spot cache remain: $count removed: $removed"; # if isdbg('rbn');
	foreach my $dxchan (DXChannel::get_all()) {
		next unless $dxchan->is_rbn;
		my $nq = keys %{$dxchan->{queue}};
		my $pc = $dxchan->{noraw10} ? sprintf("%.1f%%",$dxchan->{norbn10}*100/$dxchan->{noraw10}) : '0.0%';
		dbg "RBN:STATS 10-minute $dxchan->{call} queue: $nq raw: $dxchan->{noraw10} retrieved spots: $dxchan->{norbn10} ($pc) delivered: $dxchan->{nospot10} after filtering to  users: " . scalar keys %{$dxchan->{nousers10}};
		$dxchan->{noraw10} = $dxchan->{norbn10} = $dxchan->{nospot10} = 0; $dxchan->{nousers10} = {};
	}
}

sub per_hour
{
	foreach my $dxchan (DXChannel::get_all()) {
		next unless $dxchan->is_rbn;
		my $nq = keys %{$dxchan->{queue}};
		my $pc = $dxchan->{norawhour} ? sprintf("%.1f%%",$dxchan->{norbnhour}*100/$dxchan->{norawhour}) : '0.0%';
		dbg "RBN:STATS hour $dxchan->{call} queue: $nq raw: $dxchan->{norawhour} retrieved spots: $dxchan->{norbnhour} ($pc) delivered: $dxchan->{nospothour} after filtering to users: " . scalar keys %{$dxchan->{nousershour}};
		$dxchan->{norawhour} = $dxchan->{norbnhour} = $dxchan->{nospothour} = 0; $dxchan->{nousershour} = {};
	}
}

sub finish
{
	write_cache();
}

sub write_cache
{
	my $ta = [ gettimeofday ];
	$json->indent(1)->canonical(1) if isdbg 'rbncache';
	my $s = eval {$json->encode($spots)};
	if ($s) {
		my $fh = IO::File->new(">$cachefn") or confess("writing $cachefn $!");
		$fh->print($s);
		$fh->close;
	} else {
		dbg("RBN:Write_cache error '$@'");
		return;
	}
	$json->indent(0)->canonical(0);
	my $diff = _diffms($ta);
	my $size = sprintf('%.3fKB', (length($s) / 1000));
	dbg("RBN:WRITE_CACHE size: $size time to write: $diff mS");
}

sub check_cache
{
	if (-e $cachefn) {
		my $mt = (stat($cachefn))[9];
		my $t = $main::systime - $mt || 1;
		my $p = difft($mt, 2);
		if ($t < $cache_valid) {
			dbg("RBN:check_cache '$cachefn' spot cache exists, created $p ago and not too old");
			my $fh = IO::File->new($cachefn);
			my $s;
			if ($fh) {
				local $/ = undef;
				$s = <$fh>;
				dbg("RBN:check_cache cache read size " . length $s);
				$fh->close;
			} else {
				dbg("RBN:check_cache file read error $!");
				return undef;
			}
			if ($s) {
				eval {$spots = $json->decode($s)};
				if ($spots && ref $spots) {	
					if (exists $spots->{VERSION} && $spots->{VERSION} == $DATA_VERSION) {
						# now clean out anything that has spot build ups in progress
						while (my ($k, $cand) = each %$spots) {
							next if $k eq 'VERSION';
							next if $k =~ /^O\|/;
							next if $k =~ /^SKIM\|/;
							if (@$cand > CData) {
								$spots->{$k} = [$cand->[CTime], $cand->[CQual]];
							}
						}
						dbg("RBN:check_cache spot cache restored");
						return 1;
					} 
				}
				dbg("RBN::checkcache error decoding $@");
			}
		} else {
			my $d = difft($main::systime-$cache_valid);
			dbg("RBN::checkcache '$cachefn' created $p ago is too old (> $d), ignored");
		}
	} else {
		dbg("RBN:check_cache '$cachefn' spot cache not present");
	}
	
	return undef;
}

1;
