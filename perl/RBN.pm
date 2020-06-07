#
# The RBN connection system
#
# Copyright (c) 2020 Dirk Koopman G1TLH
#

use warnings;
use strict;

package RBN;

use 5.10.1;

use DXUtil;
use DXDebug;
use DXLog;
use DXUser;
use DXChannel;
use Math::Round qw(nearest);
use Date::Parse;

our @ISA = qw(DXChannel);

our $startup_delay =5*60; 		# don't send anything out until this timer has expired
                                # this is to allow the feed to "warm up" with duplicates
                                # so that the "big rush" doesn't happen. 

our $minspottime = 60*60;		# the time between respots of a callsign - if a call is
                                # still being spotted (on the same freq) and it has been
                                # spotted before, it's spotted again after this time
                                # until the next minspottime has passed.

our %hfitu = (
			  1 => [1, 2,],
			  2 => [1, 2, 3,],
			  3 => [2,3, 4,],
			  4 => [3,4, 9,],
#			  5 => [0],
			  6 => [7],
			  7 => [7, 6, 8, 10],
			  8 => [7, 8, 9],
			  9 => [8, 9],
			  10 => [10],
			  11 => [11],
			  12 => [12, 13],
			  13 => [12, 13],
			  14 => [14, 15],
			  15 => [15, 14],
			  16 => [16],
			  17 => [17],
			 );

sub new 
{
	my $self = DXChannel::alloc(@_);

	# routing, this must go out here to prevent race condx
	my $pkg = shift;
	my $call = shift;

	DXProt::_add_thingy($main::routeroot, [$call, 0, 0, 1, undef, undef, $self->hostname], );
	$self->{d} = {};
	$self->{spot} = {};
	$self->{last} = 0;
	$self->{noraw} = 0;
	$self->{nospot} = 0;
	$self->{norbn} = 0;
	$self->{sort} = 'N';
	$self->{lasttime} = $main::systime;
	$self->{minspottime} = $minspottime;
	$self->{showstats} = 0;

	return $self;
}

sub start
{ 
	my ($self, $line, $sort) = @_;
	my $user = $self->{user};
	my $call = $self->{call};
	my $name = $user->{name};
	my $dref = $self->{d};
	my $spotref = $self->{spot};
		
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
		$self->{hostname} = $h if $h;
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
	
	$self->{spotsfilter} = Filter::read_in('spots', $call, 0) 
		|| Filter::read_in('spots', $nossid, 0)
			|| Filter::read_in('spots', 'user_default', 0);

	# clean up qra locators
	my $qra = $user->qra;
	$qra = undef if ($qra && !DXBearing::is_qra($qra));
	unless ($qra) {
		my $lat = $user->lat;
		my $long = $user->long;
		$user->qra(DXBearing::lltoqra($lat, $long)) if (defined $lat && defined $long);  
	}

	# start inrush timer
	$self->{inrushpreventor} = $main::systime + $startup_delay;
}

sub normal
{
	my $self = shift;
	my $line = shift;
	my @ans;
	my $d = $self->{d};
	my $spot = $self->{spot};
	
	# save this for them's that need it
	my $rawline = $line;
	
	# remove leading and trailing spaces
	chomp $line;
	$line =~ s/^\s*//;
	$line =~ s/\s*$//;

	# add base RBN

	my $tim = $main::systime;

	# parse line
	dbg "RBN:RAW,$line" if isdbg('rbnraw');
	return unless $line=~/^DX\s+de/;

	my (undef, undef, $origin, $qrg, $call, $mode, $s, $m, $spd, $u, $sort, $t, $tx) = split /[:\s]+/, $line;

	# fix up FT8 spots from 7001
	$t = $u, $u = '' if !$t && is_ztime($u);
	$t = $sort, $sort = '' if !$t && is_ztime($sort);
	my $qra = $spd, $spd = '' if is_qra($spd);
	$u = $qra if $qra;

	$origin =~ s/\-(?:\d{1,2}\-)?\#$//; # get rid of all the crap we aren't interested in


	$sort ||= '';
	$tx ||= '';
	$qra ||= '';
    dbg qq{or:$origin qr:$qrg ca:$call mo:$mode s:$s m:$m sp:$spd u:$u sort:$sort t:$t tx:$tx qra:$qra} if isdbg('rbn');

	
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
			$mode = $sort;
			$t = $tx;
		}
		if ($sort && $sort eq 'BEACON') {
			$mode = 'BECON';
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
		++$self->{noraw};
		return if $d->{$p};

		# new RBN input
		$d->{$p} = $tim;
		++$self->{norbn};
		$qrg = sprintf('%.1f', nearest(.1, $qrg));     # to nearest 100Hz (to catch the odd multiple decpl QRG [eg '7002.07']).
		if (isdbg('rbnraw')) {
			my $ss = join(',', "RBN", $origin, $qrg, $call, $mode, $s, $m, $spd, $u, $sort, $t);
			$ss .= ",$b" if $b;
			dbg "RBNRAW:$ss";
		}

		# Determine whether to "SPOT" it based on whether we have not seen it before (near this QRG) or,
		# if we have, has it been a "while" since the last time we spotted it? If it has been spotted
		# before then "RESPOT" it.
		my $nqrg = nearest(1, $qrg);  # normalised to nearest Khz
		my $sp = "$call|$nqrg";		  # hopefully the skimmers will be calibrated at least this well! 
		my $ts = $spot->{$sp};

		if (!$ts || ($self->{minspottime} > 0 && $tim - $ts >= $self->{minspottime})) {
			++$self->{nospot};
			my $tag = $ts ? "RESPOT" : "SPOT";
			$t .= ",$b" if $b;

			my ($hh,$mm) = $t =~ /(\d\d)(\d\d)Z$/;
			my $utz = str2time(sprintf('%02d:%02dZ', $hh, $mm));
			dbg "RBN:" . join(',', $tag, $origin, $qrg, $call, $mode, $s, $m, $spd, $u, $sort, $t) if dbg('rbn');


			my @s = Spot::prepare($qrg, $call, $utz, sprintf("%-5s%3d $m", $mode, $s), $origin);

			if (isdbg('progress')) {
				my $d = ztime($s[2]);
				my $s = "RBN: $s[1] on $s[0] \@ $d by $s[4]";
				$s .= $s[3] ? " '$s[3]'" : q{ ''};
				$s .=  " route: $self->{call}";
				dbg($s);
			}
			
			send_dx_spot($self, $line, $mode, \@s) unless $self->{inrushpreventor} > $main::systime;

			$spot->{$sp} = $tim;
		}
	} else {
		dbg "RBN:DATA,$line" if isdbg('rbn');
	}

	# periodic clearing out of the two caches
	if (($tim % 60 == 0 && $tim > $self->{last}) || ($self->{last} && $tim >= $self->{last} + 60)) {
		my $count = 0;
		my $removed = 0;

		while (my ($k,$v) = each %{$d}) {
			if ($tim-$v > 60) {
				delete $d->{$k};
				++$removed
			} else {
				++$count;
			}
		}
		dbg "RBN:ADMIN,rbn cache: $removed removed $count remain" if isdbg('rbn');
		$count = $removed = 0;
		while (my ($k,$v) = each %{$spot}) {
			if ($tim-$v > $self->{minspottime}*2) {
				delete $spot->{$k};
				++$removed;
			} else {
				++$count;
			}
		}
		dbg "RBN:ADMIN,spot cache: $removed removed $count remain" if isdbg('rbn');

		dbg "RBN:" . join(',', "STAT", $self->{noraw}, $self->{norbn}, $self->{nospot}) if $self->{showstats};
		$self->{noraw} = $self->{norbn} = $self->{nospot} = 0;

		$self->{last} = int($tim / 60) * 60;
	}
}

# we only send to users and we send the original line (possibly with a
# Q:n in it)
sub send_dx_spot
{
	my $self = shift;
	my $line = shift;
	my $mode = shift;
	my $sref = shift;
	
	my @dxchan = DXChannel::get_all();

	foreach my $dxchan (@dxchan) {
		next unless $dxchan->is_user;
		my $user = $dxchan->{user};
		next unless $user &&  $user->wantrbn;

		my $want = 0;
		++$want if $user->wantbeacon && $mode =~ /^BEA|NCD/;
		++$want if $user->wantcw && $mode =~ /^CW/;
		++$want if $user->wantrtty && $mode =~ /^RTTY/;
		++$want if $user->wantpsk && $mode =~ /^PSK/;
		++$want if $user->wantcw && $mode =~ /^CW/;
		++$want if $user->wantft && $mode =~ /^FT/;

		++$want unless $want;	# send everything if nothing is selected.

		
		$self->dx_spot($dxchan, $sref) if $want;
	}
}

sub dx_spot
{
	my $self = shift;
	my $dxchan = shift;
	my $sref = shift;
	
#	return unless $dxchan->{rbn};

	my ($filter, $hops);

	if ($dxchan->{rbnfilter}) {
		($filter, $hops) = $dxchan->{rbnfilter}->it($sref);
		return unless $filter;
	} elsif ($self->{rbnfilter}) {
		($filter, $hops) = $self->{rbnfilter}->it($sref);
		return unless $filter;
	}

#	dbg('RBN::dx_spot spot: "' . join('","', @$sref) . '"') if isdbg('rbn');

	my $buf;
	if ($self->{ve7cc}) {
		$buf = VE7CC::dx_spot($dxchan, @$sref);
	} else {
		$buf = $self->format_dx_spot(@$sref);
		$buf =~ s/\%5E/^/g;
	}
	$dxchan->local_send('N', $buf);
}

sub format_dx_spot
{
	my $self = shift;

	my $t = ztime($_[2]);
	my $clth = $self->{consort} eq 'local' ? 29 : 30;
	my $comment = $_[3] || '';
	my $loc = '';
	my $ref = DXUser::get_current($_[1]);
	if ($ref && $ref->qra) {
		$loc = ' ' . substr($ref->qra, 0, 4);
	}
	$comment .= ' ' x ($clth - (length($comment)+length($loc)+1));
	$comment .= $loc;
	$loc = '';
	my $ref = DXUser::get_current($_[4]);
	if ($ref && $ref->qra) {
		$loc = ' ' . substr($ref->qra, 0, 4);
	}
	return sprintf "RB de %-7.7s%11.1f  %-12.12s %-s $t$loc", "$_[4]:", $_[0], $_[1], $comment;
}
1;
