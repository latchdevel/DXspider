#
# A set of routine for decode TAF and METAR a bit better and more comprehensively
# than some other products I tried.
#
# $Id$
#
# Copyright (c) 2003 Dirk Koopman G1TLH
#

package Geo::TAF;

use 5.005;
use strict;
use vars qw($VERSION);

$VERSION = '1.05';


my %err = (
		'1' => "No valid ICAO designator",
		'2' => "Length is less than 10 characters",
		'3' => "No valid issue time",
		'4' => "Expecting METAR or TAF at the beginning",
		);

my %clt = (
		SKC		=> 1,
		CLR   	=> 1,
		NSC   	=> 1,
		NSD   	=> 1,
		'BLU+'	=> 1,
		BLU		=> 1,
		WHT   	=> 1,
		GRN   	=> 1,
		YLO   	=> 1,
		YLO1  	=> 1,
		YLO2  	=> 1,
		AMB   	=> 1,
		RED   	=> 1,
		BKN   	=> 1,
		NIL   	=> 1,
		'///' 	=> 1,
		);

my %ignore = (
		'AUTO' => 1, # Automatic weather system in usage
		'COR'  => 1, # Correction issued (US)
		'CCA'  => 1, # Correction issued (EU)
		);

# Preloaded methods go here.

sub new
{
	my $pkg = shift;
	my $self = bless {@_}, $pkg;
	$self->{chunk_package} ||= "Geo::TAF::EN";
	return $self;
}

sub metar
{
	my $self = shift;
	my $l = shift;
	return 2 unless length $l > 10;
	$l = 'METAR ' . $l unless $l =~ /^\s*(?:METAR|TAF|SPECI)\s/i;
	return $self->decode($l);
}

sub taf
{
	my $self = shift;
	my $l = shift;
	return 2 unless length $l > 10;
	$l = 'TAF ' . $l unless $l =~ /^\s*(?:METAR|TAF|SPECI)\s/i;
	return $self->decode($l);
}

sub speci
{
	my $self = shift;
	my $l = shift;
	return 2 unless length $l > 10;
	$l = 'SPECI ' . $l unless $l =~ /^\s*(?:METAR|TAF|SPECI)\s/i;
	return $self->decode($l);
}

sub as_string
{
	my $self = shift;
	return join ' ', $self->as_strings;
}

sub as_strings
{
	my $self = shift;
	my @out;
	for (@{$self->{chunks}}) {
		next if $_->type =~ m/^Geo::TAF::[A-Z]+::IGNORE$/;
		push @out, $_->as_string;
	}
	return @out;
}

sub chunks
{
	my $self = shift;
	return exists $self->{chunks} ? @{$self->{chunks}} : ();
}

sub as_chunk_strings
{
	my $self = shift;
	my @out;

	for (@{$self->{chunks}}) {
		push @out, $_->as_chunk;
	}
	return @out;
}

sub as_chunk_string
{
	my $self = shift;
	return join ' ', $self->as_chunk_strings;
}

sub raw
{
	return shift->{line};
}

sub is_weather
{
	return $_[0] =~ /^\s*(?:(?:METAR|TAF|SPECI)\s+)?[A-Z]{4}\s+\d{6}Z?\s+/;
}

sub errorp
{
	my $self = shift;
	my $code = shift;
	return $err{"$code"};
}

# basically all metars and tafs are the same, except that a metar is short
# and a taf can have many repeated sections for different times of the day
sub decode
{
	my $self = shift;
	my $l = uc shift;

	$l =~ s/=$//;

	my @tok = split /\s+/, $l;

	$self->{line} = join ' ', @tok;

	# Count how many problems we have
	$self->{decode_failures} = 0;

	# do we explicitly have a METAR, SPECI or TAF
	my $t = shift @tok;
	if ($t =~ /^(TAF|METAR|SPECI)$/) {
		$self->{report_type} = $t;
		$self->{taf} = $t eq 'TAF';
	} else {
	    return 4;
	}

	# next token is the ICAO dseignator
	$t = shift @tok;
	if ($t =~ /^[A-Z]{4}$/) {
		$self->{icao} = $t;
	} else {
		return 1;
	}

	# next token is an issue time
	$t = shift @tok;
	if (my ($day, $time) = $t =~ /^(\d\d)(\d{4})Z?$/) {
		$self->{day} = $day;
		$self->{time} = _time($time);
	} else {
		return 3;
	}

	# if it is a TAF then expect a validity (may be missing)
	if ($self->{taf}) {
		if (my ($vd, $vfrom, $vto) = $tok[0] =~ /^(\d\d)(\d\d)(\d\d)$/) {
			$self->{valid_day} = $vd;
			$self->{valid_from} = _time($vfrom * 100);
			$self->{valid_to} = _time($vto * 100);
			shift @tok;
		} 
	}

	# we are now into the 'list' of things that can repeat over and over

	my @chunk = (
				 $self->_chunk('HEAD', $self->{report_type},
							   $self->{icao}, $self->{day}, $self->{time}),
				 $self->_chunk('BLOCK'), # new block always now
				);

	if($self->{valid_day}) {
		push @chunk, $self->_chunk('VALID');
		push @chunk, $self->_chunk('PERIOD', $self->{valid_from}, $self->{valid_to}, $self->{valid_day}, );
		push @chunk, $self->_chunk('BLOCK'); # new block always now
	}

	my ($c0, $c1, $expect, @remark_buffer, $ignore_no_length_change);
	my ($day, $time, $percent, $sort, $dir);
	my ($wdir, $spd, $gust, $unit);
	my ($viz, $vunit);
	my ($m, $p);

	while (@tok) {
		$t = shift @tok;
		# Count number of items in chunk, and use to determine if we could not
		# decode.
		$c0 = $#chunk;
		# If this is NOT set, and the count doesn't change, we failed a decode
		$ignore_no_length_change = 0;

		# This is just so the rest patches easier
		if(!defined($t)) {

		# temporary 
		} elsif ($t eq 'TEMPO' || $t eq 'TEMP0' || $t eq 'BECMG') {
			# TEMPO occurs with both a oh and a zero, in some bad automated hardware
			$t = 'TEMPO' if $t eq 'TEMP0';
			push @chunk, $self->_chunk('BLOCK'); # new block always now
			push @chunk, $self->_chunk($t);
			$expect = 'PERIOD';

		# time range
		} elsif ($expect eq 'PERIOD' || $t =~ /^(\d\d)(\d\d)\/(\d\d)(\d\d)$/) {
			undef $expect;
			# next token may be a period if it is a taf
			# Two possible formats:
			# XXYY = hour XX to hour YY (but only valid after TEMPO/BECMG)
			# AABB/CCDD = day aa hour bb TO day cc hour dd (after TEMPO/BECMG, but ALSO valid after HEAD)
			my ($from_time, $to_time, $from_day, $to_day);
			my ($got_time, $got_day);
			if (($from_time, $to_time) = $t =~ /^(\d\d)(\d\d)$/) {
				$got_time = 1;
			} elsif (($from_day, $from_time, $to_day, $to_time) = $t =~ /^(\d\d)(\d\d)\/(\d\d)(\d\d)$/) {
				$got_time = $got_day = 1;
			}
			if ($got_time && $self->{taf} && $from_time >= 0 && $from_time <= 24 && $to_time >= 0 && $to_time <= 24) {
				$from_time = _time($from_time * 100);
				$to_time = _time($to_time * 100);
			} else {
				undef $from_time;
				undef $to_time;
				undef $got_time;
			}
			if($got_time && $got_day && $from_day >= 1 && $from_day <= 31 && $to_day >= 1 && $to_day <= 31) {
				# do not shift tok, we did it already
			} else {
				undef $from_day;
				undef $to_day;
				undef $got_day;
			}
			push @chunk, $self->_chunk('PERIOD', $from_time, $to_time, $from_day, $to_day) if $got_time;

		# ignore
		} elsif ($ignore{$t}) {
			push @chunk, $self->_chunk('IGNORE', $t);

		# no sig weather
		} elsif ($t eq 'NOSIG' || $t eq 'NSW') {
			push @chunk, $self->_chunk('WEATHER', 'NOSIG');

		# // means the automated system cannot determine the precipiation at all
		} elsif ($t eq '//') {
			push @chunk, $self->_chunk('WEATHER', $t);

		# specific broken on its own
		} elsif ($t eq 'BKN') {
			push @chunk, $self->_chunk('WEATHER', $t);

		# wind shear (is followed by a runway designation)
		} elsif ($t eq 'WS') {
			push @chunk, $self->_chunk('WEATHER', $t);

		# other 3 letter codes
		} elsif ($clt{$t}) {
			push @chunk, $self->_chunk('CLOUD', $t);

		# EU CAVOK viz > 10000m, no cloud, no significant weather
		} elsif ($t eq 'CAVOK') {
			$self->{viz_dist} ||= ">10000";
			$self->{viz_units} ||= 'm';
			push @chunk, $self->_chunk('CLOUD', 'CAVOK');

		# RMK group (end for now)
		} elsif ($t eq 'RMK' or $t eq 'RKM') {
			#push @chunk, $self->_chunk('RMK', join(' ',@tok));
			$self->{in_remark} = $c0;
			push @chunk, $self->_chunk('BLOCK'); # new block always now
			#last;

		# from
		} elsif (($day,$time) = $t =~ /^FM(\d\d)?(\d\d\d\d)Z?$/ ) {
			push @chunk, $self->_chunk('BLOCK'); # new block always now
			push @chunk, $self->_chunk('FROM', _time($time), $day);

		# Until
		} elsif (($day,$time) = $t =~ /^TL(\d\d)?(\d\d\d\d)Z?$/ ) {
			push @chunk, $self->_chunk('BLOCK'); # new block always now
			push @chunk, $self->_chunk('TIL', _time($time), $day);

		# At
		# Seen at http://stoivane.iki.fi/metar/
		} elsif (($day,$time) = $t =~ /^AT(\d\d)?(\d\d\d\d)Z?$/ ) {
			push @chunk, $self->_chunk('BLOCK'); # new block always now
			push @chunk, $self->_chunk('AT', _time($time), $day);

		# probability
		} elsif (($percent) = $t =~ /^PROB(\d\d)$/ ) {
			push @chunk, $self->_chunk('BLOCK'); # new block always now
			$expect = 'PERIOD';
			push @chunk, $self->_chunk('PROB', $percent);

		# runway
		} elsif (($sort, $dir) = $t =~ /^(RWY?|LDG|TKOF|R)(\d\d\d?[RLC]?)$/ ) {
			# Special case,
			# there is a some broken METAR hardware out there that codes:
			# 'RWY01 /0100VP2000N'
			# TODO: include the full regex here
			if($tok[0] =~ /^\/[MP]?\d{4}/) {
				$t .= shift @tok;
				unshift @tok, $t
			}
			push @chunk, $self->_chunk('RWY', $sort, $dir);

		# runway, but as seen in wind shear
		# eg: LDG RWY25L
		} elsif (($sort) = $t =~ /^(LDG|TKOF)$/ ) {
			my $t2;
			$t2 = shift @tok;
			($dir) = $t2 =~ /^RWY(\d\d[RLC]?)$/;
			push @chunk, $self->_chunk('RWY', $sort, $dir);

		# a wind group
		} elsif (($wdir, $spd, $gust, $unit) = $t =~ /^([\dO]{3}|VRB|\/{3})([\dO]{2}|\/{2})(?:G([\dO]{2,3}))?(KTS?|MPH|MPS|KMH)$/) {
			my ($fromdir, $todir);

			# More hardware suck, oh vs. zero
			$wdir =~ s/O/0/g if $wdir;
			$spd  =~ s/O/0/g if $spd;
			$gust =~ s/O/0/g if $gust;

			# it could be variable so look at the next token
			if	(@tok && (($fromdir, $todir) = $tok[0] =~ /^([\dO]{3})V([\dO]{3})$/)) {
				shift @tok;
				$fromdir =~ s/O/0/g;
				$todir =~ s/O/0/g;
			}

			# Part of the hardware is bad
			$wdir = 'NA' if $wdir eq '///';
			$spd = 'NA' if $spd eq '//';

			$spd = 0 + $spd unless $spd eq 'NA';
			$gust = 0 + $gust if defined $gust;
			$unit = 'kt' if $unit eq 'KTS';
			$unit = ucfirst lc $unit;
			$unit = 'm/sec' if $unit eq 'Mps';
			$self->{wind_dir} ||= $wdir;
			$self->{wind_speed} ||= $spd;
			$self->{wind_gusting} ||= $gust;
			$self->{wind_units} ||= $unit;
			push @chunk, $self->_chunk('WIND', $wdir, $spd, $gust, $unit, $fromdir, $todir);

		# wind not reported
		# MHRO does not seem to follow this rule.
		} elsif ($t =~ /^\/{5}$/) {
			if($self->{icao} eq 'MHRO') {
				; # TODO: We will do something here once we figure what MHRO uses this field for
				push @chunk, $self->_chunk('IGNORE', $t);
			} else {
				push @chunk, $self->_chunk('WIND', 'NR', undef, undef, undef, undef, undef);
			}

		# pressure 
		} elsif (my ($u, $p, $punit) = $t =~ /^([QA])(?:NH)?(\d{4}|\/{4}|)(INS?)?$/) {

			$p = 'NA' if $p eq '////';
			$p = 'NA' if $p eq '' or !defined($p);
			$p = 0.0 + $p unless $p eq 'NA';
			if ($u eq 'A' || $punit && $punit =~ /^I/) {
				$p = sprintf("%.2f", $p / 100.0) unless $p eq 'NA';
				$u = 'in';
			} else {
				$u = 'hPa';
			}
			$self->{pressure} ||= $p;
			$self->{pressure_units} ||= $u;
			push @chunk, $self->_chunk('PRESS', $p, $u);

		# viz group in metres
		# May be \d{4}NDV per http://www.caa.co.uk/docs/33/CAP746.PDF
		# //// = unknown
		# strictly before the remark section. After RMK plain numbers mean other things.
		} elsif (!defined $self->{in_remark} and ($viz, $dir) = $t =~ m/^(\d\d\d\d|\/{4})([NSEW]{1,2}|NDV)?$/) {
			if($viz eq '////') {
				$viz = 'NA';
			} else {
				$viz = $viz eq '9999' ? ">10000" : 0 + $viz;
			}
			$self->{viz_dist} ||= $viz;
			$self->{viz_units} ||= 'm';
			$dir = undef if $dir && $dir eq 'NDV';
			push @chunk, $self->_chunk('VIZ', $viz, 'm', $dir);
			#push @chunk, $self->_chunk('WEATHER', $mist) if $mist;

		# viz group in integral KM, feet, M
		} elsif (($viz, $vunit) = $t =~ m/^(\d+|\/{1,3})(KM|FT|M)$/) {
			if($viz =~ /^\/+$/) {
				$viz = 'NA';
			} else {
				$viz = $viz eq '9999' ? ">10000" : 0 + $viz;
			}
			$vunit = lc $vunit;
			$self->{viz_dist} ||= $viz;
			$self->{viz_units} ||= $vunit;
			push @chunk, $self->_chunk('VIZ', $viz, $vunit);

		# viz group in miles and faction of a mile with space between
		} elsif (my ($m) = $t =~ m/^(\d)$/) {
			if (@tok && (($viz) = $tok[0] =~ m/^(\d\/\d)SM$/)) {
				shift @tok;
				$viz = "$m $viz";
				$self->{viz_dist} ||= $viz;
				$self->{viz_units} ||= 'miles';
				push @chunk, $self->_chunk('VIZ', $viz, 'miles');
			}

		# viz group in miles (either in miles or under a mile)
		} elsif (my ($lt, $viz) = $t =~ m/^(M|P)?(\d+(:?\/\d)?|\/{1,3})SM$/) {
			if($viz =~ /^\/+$/) {
				$viz = 'NA';
			}
			$viz = '<' . $viz if $lt eq 'M';
			$viz = '>' . $viz if $lt eq 'P';
			$self->{viz_dist} ||= $viz;
			$self->{viz_units} ||= 'Stat. Miles';
			push @chunk, $self->_chunk('VIZ', $viz, 'miles');

		# Runway deposits state per ICAO
		# 8 digits
		# (DR,DR),ER,CR,(eR,eR),(BR,BR)
		# "ER,CR,eR,eR" == CLRD when previous deposits are removed
		# Also an alternate form, xxyzCLRD.
		} elsif (my ($rwy, $type, $extent, $depth, $braking) = $t =~ m/^(\d\d)(\d|\/|C)(\d|\/|L)(\d\d|\/\/|RD|CL)(\d\d|\/\/|RD)$/) {
			# Runway desginator
			if($rwy == 99) {
				$rwy = 'LAST';
			} elsif($rwy == 88) {
				$rwy = 'ALL';
			} elsif($rwy >= 50) {
				$rwy = ($rwy-50).'R';
			} else {
				$rwy = $rwy.'L';
			}

			# Type
			# Not processed here

			# Extent
			# Not processed here

			# Depth
			if($depth eq 'RD' or $depth eq 'CL') {
				# Previous contaminination cleared
				$type = 'CLRD';
				$extent = undef;
				$depth = undef;
				$braking = undef if $braking eq 'RD';
			} elsif($depth eq '//') {
				; # pass-thru
			} elsif($depth == 0) {
				$depth = '<1mm';
			} elsif($depth <= 90) {
				$depth .= 'mm';
			} elsif($depth == 91) {
				# BAD!
			} elsif($depth >= 92 && $depth <= 97) {
				# 92 = 10cm ... 97 = 35cm
				$depth = sprintf('%dcm', (($depth - 90) * 5));
			} elsif($depth == 99) {
				$depth = '>40cm';
			} elsif($depth == 99) {
				$extent = 'CVRD';
				$depth = 'NR';
			}

			# Friction / Breaking action
			if(defined($braking) && $braking < 91) {
				$braking = sprintf('%.2f', $braking/100.0);
			} # Other codes are handling in the print

			push @chunk, $self->_chunk('DEP', $rwy, $type, $extent, $depth, $braking);

		# runway visual range
		} elsif (my ($rw, $rlt, $range, $vlt, $var, $runit, $tend) = $t =~ m/^R(\d\d\d?[LRC]?)\/([MP])?(\d\d\d\d?)(?:V([MP])?(\d\d\d\d?))?((?:FT)\/?)?([UND])?$/) {
			$runit = 'm' unless defined($runit) && length($runit) > 0;
			$runit = lc $runit;
			$range = "<$range" if $rlt && $rlt eq 'M';
			$range = ">$range" if $rlt && $rlt eq 'P';
			$var = "<$var" if $vlt && $vlt eq 'M';
			$var = ">$var" if $vlt && $vlt eq 'P';
			push @chunk, $self->_chunk('RVR', $rw, $range, $var, $runit, $tend);

		# weather
		} elsif (not defined $self->{in_remark} && my ($deg, $w) = $t =~ /^(\+|\-)?([A-Z][A-Z]{1,6})$/) {
			push @chunk, $self->_chunk('WEATHER', $deg, $w =~ /([A-Z][A-Z])/g);
		# cloud and stuff
		# /// is the TCU column means that the automated system is unable to detect it
		} elsif (my ($amt, $height, $cb) = $t =~ m/^(FEW|SCT|BKN|OVC|SKC|CLR|VV|\/{3})(\d\d\d|\/{3})(CB|TCU|CBMAM|ACC|CLD|\/\/\/)?$/) {
			push @chunk, $self->_chunk('CLOUD', $amt, $height eq '///' ? 0 : $height * 100, $cb);

		# temp / dew point
		} elsif (my ($ms, $temp, $n, $d) = $t =~ m/^(M)?(\d\d)\/(M)?(\d\d)?$/) {
			$temp = 0 + $temp;
			$d = 0 + $d;
			$temp = -$temp if defined $ms;
			$d = -$d if defined $d && defined $n;
			$self->{temp} ||= $temp;
			$self->{dewpoint} ||= $d;
			push @chunk, $self->_chunk('TEMP', $temp, $d);
		
		# Remark section containing exact cloud type + okta number
		# cloud type codes in Geo::TAF::EN::CLOUD
		# example: CI1AC1TCU4 = Cirrus 1/8, Altocumulus 1/8, Towering Cumulus 4/8
		# example: SN2SC1SC3SC2
		} elsif (my $ct = $t =~ m/^((?:CI|CS|CC|AS|AC|ACC|ST|NS|SC|SF|SN|CF|CU|TCU|CB)\d)+$/) {
			foreach my $ct (split m/((?:CI|CS|CC|AS|AC|ACC|ST|NS|SC|SF|SN|CF|CU|TCU|CB)\d)/, $t) {
				chomp $ct;
				next if(length($ct) == 0);
				$t = $ct;
				$ct =~ s/\d+$//;
				$t =~ s/^$ct//;
				push @chunk, $self->_chunk('CLOUD', $t, $ct)
			}

		# pressure equivilent @ sea level
		} elsif (($p) = $t =~ /^SLP(\d\d\d)$/) {
			$p = 0+$p;
			$p = sprintf '%.1f', 1000+$p/10.0;
			push @chunk, $self->_chunk('SLP', $p, 'hPa');

		# station type
		} elsif (defined $self->{in_remark} && ($type) = $t =~ /^AO(1|2)$/) {
			$type = ($type == '1' ? '-' : '+').'PRECIP';
			push @chunk, $self->_chunk('STATION_TYPE', $type);

		# US NWS:
		# Hourly Precipitation Amount (P)
		# 3- and 6-Hour Precipitation Amount (3, 6)
		# 24-Hour Precipitation Amount (7)
		#
		# The specification says 4 digits after the type code, but some stations only have 3:
		# CXKA 011100Z AUTO 35002KT M28/M31 RMK AO1 3010 SLP219 T12761306 50023
		# ^^^ 0.1 inches in the 3 hour period
		#
		# KW22 011135Z AUTO 23016G23KT 10SM BKN029 OVC036 02/M02 A2988 RMK A02 P000
		# ^^^ 0.0 inches in the last hour
		} elsif (defined $self->{in_remark} && my ($precip_period, $precip) = $t =~ /^(3|6|7|P)(\d{3,4})$/) {
			$precip_period = 24 if $precip_period eq '7';
			$precip_period = 1 if $precip_period eq 'P';
			push @chunk, $self->_chunk('PRECIP', $precip, $precip_period);

		# other remarks go to a text buffer for now
		#} elsif (defined $self->{in_remark} && length($t) > 0) {
		} elsif (defined $self->{in_remark}) {
			print "Adding to remark buffer: $t\n";
			push @remark_buffer, $t;
			$ignore_no_length_change = 1;

		#X#} elsif (1) {
		#X#	print "Debug marker: $t\n";
		#X#	$ignore_no_length_change = 1;

		} elsif(0) {


		# End of processing
		}

		$c1 = $#chunk;
		if($c0 == $c1 && $ignore_no_length_change == 0) {
			push @chunk, $self->_chunk('RMK','Failed to decode: '.$t);
			$self->{decode_failures}++;
		}
	}

	if (@remark_buffer) {
		push @chunk, $self->_chunk('BLOCK') unless ($c0 == $c1);
		push @chunk, $self->_chunk('RMK', join(' ', @remark_buffer));
	}
	$self->{chunks} = \@chunk;
	return undef;	
}

sub _pkg
{
	my $self = shift;
	my $pkg = shift;
	no strict 'refs';
	$pkg = $self->{chunk_package} . '::' . $pkg;
	return $pkg;
}
sub _chunk
{
	my $self = shift;
	my $pkg = shift;
	no strict 'refs';
	$pkg = $self->_pkg($pkg);
	return $pkg->new(@_);
}

sub _time
{
	return sprintf "%02d:%02d", unpack "a2a2", sprintf "%04d", shift;
}

# accessors
sub AUTOLOAD
{
	no strict;
	my ($package, $name) = $AUTOLOAD =~ /^(.*)::(\w+)$/;
	return if $name eq 'DESTROY';

	*$AUTOLOAD = sub {return $_[0]->{$name}};
	goto &$AUTOLOAD;
}

#
# these are the translation packages
#
# First the factory method
#

package Geo::TAF::EN;
sub type { return __PACKAGE__; }

sub new
{
	my $pkg = shift;
	return bless [@_], $pkg; 
}

sub as_chunk
{
	my $self = shift;
	my ($n) = (ref $self) =~ /::(\w+)$/;
	return '[' . join(' ', $n, map {defined $_ ? $_ : '?'} @$self) . ']';
}

sub as_string
{
	my $self = shift;
	my ($n) = (ref $self) =~ /::(\w+)$/;
	return join ' ', ucfirst $n, map {defined $_ ? $_ : ()} @$self;
}

sub day
{
	my $pkg = shift;
	my $d = sprintf "%d", ref($pkg) ? shift : $pkg;
	if ($d =~ /1$/) {
		return "${d}st";
	} elsif ($d =~ /2$/) {
		return "${d}nd";
	} elsif ($d =~ /3$/) {
		return "${d}rd";
	}
	return "${d}th";
}

package Geo::TAF::EN::HEAD;
use vars qw(@ISA);
@ISA = qw(Geo::TAF::EN);
sub type { return __PACKAGE__; }

sub as_string
{
	my $self = shift;
	return sprintf "%s for %s issued at %s on %s", $self->[0], $self->[1], $self->[3], $self->day($self->[2]);
}

package Geo::TAF::EN::VALID;
use vars qw(@ISA);
@ISA = qw(Geo::TAF::EN);

sub as_string
{
	my $self = shift;
	return "valid";
	# will be followed by a PERIOD block
}


package Geo::TAF::EN::WIND;
use vars qw(@ISA);
@ISA = qw(Geo::TAF::EN);
sub type { return __PACKAGE__; }

my %wst = (
	NA	=> 'unknown',
	NR	=> 'not reported',
	VRB	=> 'variable',
);

# $direction, $speed, $gusts, $unit, $fromdir, $todir
sub as_string
{
	my $self = shift;
	my $out;
	$out  = sprintf("wind %s", ($wst{$self->[0]} ? $wst{$self->[0]}: $self->[0]));
	$out .= sprintf(" varying between %s && %s", $self->[4], $self->[5]) if defined $self->[4];
	$out .= sprintf("%s at %s", ($self->[0] eq 'VRB' ? '' : " degrees"), $wst{$self->[1]} ? $wst{$self->[1]} : $self->[1]) if defined $self->[1];
	$out .= sprintf(" gusting %s", $self->[2]) if defined $self->[2] && $self->[1] ne 'NA';
	$out .= $self->[1] eq 'NA' ? ' speed' : $self->[3] if defined $self->[3];
	return $out;
}

package Geo::TAF::EN::PRESS;
use vars qw(@ISA);
@ISA = qw(Geo::TAF::EN);
sub type { return __PACKAGE__; }

# $pressure, $unit
sub as_string
{
	my $self = shift;
	return sprintf "QNH pressure not available" if $self->[0] eq 'NA';
	return sprintf "QNH pressure %s%s", $self->[0], $self->[1];
}

package Geo::TAF::EN::SLP;
use vars qw(@ISA);
@ISA = qw(Geo::TAF::EN);
sub type { return __PACKAGE__; }

# $pressure, $unit
sub as_string
{
	my $self = shift;
	return sprintf "SLP pressure not available" if $self->[0] eq 'NA';
	return sprintf "SLP pressure %s%s", $self->[0], $self->[1];
}

# temperature, dewpoint
package Geo::TAF::EN::TEMP;
use vars qw(@ISA);
@ISA = qw(Geo::TAF::EN);
sub type { return __PACKAGE__; }

sub as_string
{
	my $self = shift;
	my $out;
	$out  = sprintf("temperature %sC", $self->[0]);
	$out .= sprintf(" dewpoint %sC", $self->[1]) if defined $self->[1];

	return $out;
}

package Geo::TAF::EN::CLOUD;
use vars qw(@ISA);
@ISA = qw(Geo::TAF::EN);
sub type { return __PACKAGE__; }

my %st = (
		VV    => 'vertical visibility',
		SKC   => "no cloud",
		CLR   => "no cloud no significant weather",
		SCT   => "3-4 oktas/scattered",
		BKN   => "5-7 oktas/broken",
		FEW   => "0-2 oktas/few",
		OVC   => "8 oktas/overcast",
		'///' => 'some',
);

my %cloud_code = (
		# Cloud codes found in remarks, followed by an okta
		# same order as the SCT/BWN/FEW/OVC codes.
		CI   => 'Cirrus',
		CS   => 'Cirrostratus',
		CC   => 'Cirrocumulus',
		AS   => 'Altostratus',
		AC   => 'Altocumulus',
		ACC  => 'Altocumulus Castellanus',
		ST   => 'Stratus',
		NS   => 'Nimbostratus',
		SC   => 'Stratoculumus',
		SF   => 'Stratus Fractus',
		CF   => 'Cumulus Fractus',
		CU   => 'Cumulus',
		TCU  => 'Towering Cumulus',
		CB   => 'Cumulonimbus',	# aka thunder clouds

		# not official, but seen often in Canada: METAR CYVR 262319Z 09011KT 1 1/2SM -SN FEW003 BKN006 OVC010 00/ RMK SN2SC1SC3SC2
		SN   => 'Snow clouds',
);

my %col = (
		'CAVOK'	=> "no cloud below 5000ft >10km visibility no significant weather (CAVOK)",
		'NSC'	=> 'no significant cloud',
		'NCD'	=> "no cloud detected",
		'BLU+'	=> '3 oktas at >2500ft >8km visibility',
		'BLU'	=> '3 oktas at 2500ft 8km visibility',
		'WHT'	=> '3 oktas at 1500ft 5km visibility',
		'GRN'	=> '3 oktas at 700ft 3700m visibility',
		'YLO1'	=> '3 oktas at 500ft 2500m visibility',
		'YLO2'	=> '3 oktas at 300ft 1600m visibility',
		'YLO'	=> '3 oktas at 300ft 1600m visibility', # YLO2 and YLO are meant to be identical
		'AMB'	=> '3 oktas at 200ft 800m visibility',
		'RED'	=> '3 oktas at <200ft <800m visibility',
		'NIL'	=> 'no weather',
);

my %st_storm = (
		CB    => 'cumulonimbus',
		TCU   => 'towering cumulus',
		CBMAM => 'cumulonimbus mammatus',
		ACC   => 'altocumulus castellatus',
		CLD   => 'standing lenticular',
		# if you get this, the automated sensors are unable to decide
		'///' => 'unknown cumulus',
);

# $amt, $height, $cb
sub as_string
{
	my $self = shift;
	return $col{$self->[0]} if @$self == 1 && $col{$self->[0]};
	if(@$self == 2 && (int($self->[0]) eq "$self->[0]") and defined $cloud_code{$self->[1]}) {
		return sprintf "%s %d/8 cover", $cloud_code{$self->[1]}, $self->[0];
	}
	return sprintf("%s %sft", $st{$self->[0]}, $self->[1]) if $self->[0] eq 'VV';
	my $out = sprintf("%s cloud", $st{$self->[0]});
	$out .= sprintf(' at %sft', $self->[1]) if $self->[1];
	$out = 'unknown cloud cover' if $self->[1] == 0 && $self->[0] eq '///';
	$out .= sprintf(" with %s", $st_storm{$self->[2]}) if $self->[2];
	return $out;
}

package Geo::TAF::EN::WEATHER;
use vars qw(@ISA);
@ISA = qw(Geo::TAF::EN);
sub type { return __PACKAGE__; }

my %wt = (
		'+'   => 'heavy',
		'-'   => 'light',
		'VC'  => 'in the vicinity',

		'MI'  => 'shallow',
		'PI'  => 'partial',
		'BC'  => 'patches of',
		'DR'  => 'low drifting',
		'BL'  => 'blowing',
		'SH'  => 'showers',
		'TS'  => 'thunderstorms containing',
		'FZ'  => 'freezing',
		'RE'  => 'recent',

		'DZ'  => 'drizzle',
		'RA'  => 'rain',
		'SN'  => 'snow',
		'SG'  => 'snow grains',
		'IC'  => 'ice crystals',
		'PE'  => 'ice pellets',
		'GR'  => 'hail',
		'GS'  => 'small hail/snow pellets',
		'UP'  => 'unknown precip',
		'//'  => 'unknown weather',

		'BR'  => 'mist',
		'FG'  => 'fog',
		'FU'  => 'smoke',
		'VA'  => 'volcanic ash',
		'DU'  => 'dust',
		'SA'  => 'sand',
		'HZ'  => 'haze',
		'PY'  => 'spray',

		'PO'  => 'dust/sand whirls',
		'SQ'  => 'squalls',
		'FC'  => 'tornado',
		'SS'  => 'sand storm',
		'DS'  => 'dust storm',
		'+FC' => 'water spouts',
		'WS'  => 'wind shear',
		'BKN' => 'broken',

		'NOSIG' => 'no significant weather',
		'PRFG'  => 'fog banks', # officially PR is a modifier of FG
		);

sub as_string
{
	my $self = shift;
	my @out;

	my ($vic, $shower);
	my @in;
	push @in, @$self;

	while (@in) {
		my $t = shift @in;

		if (!defined $t) {
			next;
		} elsif ($t eq 'VC') {
			$vic++;
			next;
		} elsif ($t eq 'SH') {
			$shower++;
			next;
		} elsif ($t eq '+' && $self->[0] eq 'FC') {
			push @out, $wt{'+FC'};
			shift;
			next;
		}

		push @out, $wt{$t};

		if (@out && $shower) {
			$shower = 0;
			push @out, $wt{'SH'};
		}
	}
	push @out, $wt{'VC'} if $vic;

	return join ' ', @out;
}

package Geo::TAF::EN::STATION_TYPE;
use vars qw(@ISA);
@ISA = qw(Geo::TAF::EN);
sub type { return __PACKAGE__; }

# $code
sub as_string
{
	my $self = shift;
	my $code = shift;
	my $out = 'Automated station';
	if($code eq '+PRECIP') {
		$out .= ' cannot detect precipitation';
	} elsif($code eq '-PRECIP') {
		$out .= ' has precipitation discriminator';
	}
}

package Geo::TAF::EN::PRECIP;
use vars qw(@ISA);
@ISA = qw(Geo::TAF::EN);
sub type { return __PACKAGE__; }

# $precip, $period
sub as_string
{
	my $self = shift;
	my $precip = $self->[0];
	my $period = $self->[1];
	if($period == 1) {
		return sprintf 'precipitation %.2f inches in last hour', $precip;
	} elsif($period == 24) {
		return sprintf '24 hour total precipitation %.2f inches', $precip;
	} else {
		return sprintf '%d-hour precipitation %.2f', $period, $precip;
	}
}

package Geo::TAF::EN::RVR;
use vars qw(@ISA);
@ISA = qw(Geo::TAF::EN);
sub type { return __PACKAGE__; }

# $rw, $range, $var, $runit, $tend;
sub as_string
{
	my $self = shift;
	my $out;
	$out  = sprintf("visual range on runway %s is %s%s", $self->[0], $self->[1], $self->[3]);
	$out .= sprintf(" varying to %s%s", $self->[2], $self->[3]) if defined $self->[2];
	if (defined $self->[4]) {
		$out .= " decreasing" if $self->[4] eq 'D';
		$out .= " increasing" if $self->[4] eq 'U';
		$out .= " unchanged"  if $self->[4] eq 'N';
	}
	return $out;
}

package Geo::TAF::EN::RWY;
use vars qw(@ISA);
@ISA = qw(Geo::TAF::EN);
sub type { return __PACKAGE__; }

my %rwy = (
		  LDG => 'landing',
		  SKC => 'take-off',
		);
sub as_string
{
	my $self = shift;
	my $out;
	if($rwy{$self->[0]}) {
		$out .= $rwy{$self->[0]} . ' ';
	}
	$out .= sprintf("runway %s", $self->[1]);
	return $out;
}

package Geo::TAF::EN::PROB;
use vars qw(@ISA);
@ISA = qw(Geo::TAF::EN);
sub type { return __PACKAGE__; }

# $percent, $from, $to;
sub as_string
{
	my $self = shift;

	return sprintf("probability %s%%", $self->[0]);
	# will be followed by a PERIOD block
}

package Geo::TAF::EN::TEMPO;
use vars qw(@ISA);
@ISA = qw(Geo::TAF::EN);
sub type { return __PACKAGE__; }

sub as_string
{
	my $self = shift;
	return "temporarily";
	# will be followed by a PERIOD block
}

package Geo::TAF::EN::BECMG;
use vars qw(@ISA);
@ISA = qw(Geo::TAF::EN);
sub type { return __PACKAGE__; }

sub as_string
{
	my $self = shift;
	return "becoming";
	# will be followed by a PERIOD block
}

package Geo::TAF::EN::PERIOD;
use vars qw(@ISA);
@ISA = qw(Geo::TAF::EN);
sub type { return __PACKAGE__; }

sub as_string
{
	my $self = shift;
	# obj, from_time, to_time, from_day, to_day
	my ($out, $format);
	$out = 'period from ';
	# format 1 = time only, no date
	# format 2 = time, one day (or two days that are the same value)
	# format 3 = time and two different day
	$format = 1 if defined $self->[0] && defined $self->[1];
	if(defined $self->[2]) {
		$format = 3;
		$format-- if not defined $self->[3] or $self->[2] == $self->[3];
	}
	if($format == 2) {
		$out .= sprintf("%s to %s on %s", $self->[0], $self->[1], $self->day($self->[2]));
	} elsif($format == 3) {
		$out .= sprintf("%s %s to %s %s", $self->day($self->[2]), $self->[0], $self->day($self->[3]), $self->[1]);
	} elsif($format == 1) {
		$out .= sprintf("%s to %s", $self->[0], $self->[1]);
	} else {
		$out .= 'BAD PERIOD';
	}

	return $out;
}

package Geo::TAF::EN::VIZ;
use vars qw(@ISA);
@ISA = qw(Geo::TAF::EN);
sub type { return __PACKAGE__; }

sub as_string
{
	my $self = shift;

	my $out = 'visibility ';
	return $out.'not available' if $self->[0] eq 'NA';
	return $out.sprintf("%s%s%s", ($self->[2] ? $self->[2].' ' : ''), $self->[0], $self->[1]);
}

package Geo::TAF::EN::DEP;
use vars qw(@ISA);
@ISA = qw(Geo::TAF::EN);
sub type { return __PACKAGE__; }

my %cover_type = (
		0		=> 'clear & dry',
		1		=> 'damp',
		2		=> 'wet/water patches',
		3		=> 'frost-covered',
		4		=> 'dry snow',
		5		=> 'wet snow',
		6		=> 'slush',
		7		=> 'ice',
		8		=> 'compacted snow',
		9		=> 'frozen ruts',
		'/'		=> 'unknown',
		'CLRD'	=> 'cleared',
		);

my %extent = (
		1		=> '<10%',
		2		=> '11-25%',
		5		=> '26-50%',
		9		=> '51-100%',
		'/'		=> 'not reported',
		'CVRD'	=> 'non-operational',
		);

my %depth = (
		'NR' => 'not reported',
		'//' => 'not significent',
		);

my %breaking = (
		95		=> 'good',
		94		=> 'medium/good',
		93		=> 'medium',
		92		=> 'medium/poor',
		91		=> 'poor',
		99		=> 'unreliable',
		'//'	=> 'not reported',
		);

# $rwy, $cover_type, $extent, $depth, $braking
sub as_string
{
	my $self = shift;

	my $out;
	$out  = sprintf 'Runway %s conditions: %s', $self->[0], $cover_type{$self->[1]};
	if(defined($self->[2])) {
		$out .= sprintf(', extent %s',$extent{$self->[2]});
	}
	if(defined($self->[3])) {
		$_ = $depth{$self->[3]};
		$_ = $self->[3] unless $_;
		$out .= sprintf(', depth %s', $_);
	}
	if(defined($self->[4])) {
		$_ = $depth{$self->[4]};
		$out .= sprintf(', braking action %s', $_) if $_;
		$out .= sprintf(', friction coefficient %s', $self->[4]) unless $_;
	}
	$out .= ';';

	return $out;
}

package Geo::TAF::EN::FROM;
use vars qw(@ISA);
@ISA = qw(Geo::TAF::EN);
sub type { return __PACKAGE__; }

sub as_string
{
	my $self = shift;

	if($self->[1]) {
		return sprintf("from %s on the %s", $self->[0],$self->day($self->[1]));
	} else {
		return sprintf("from %s", $self->[0]);
	}
}

package Geo::TAF::EN::TIL;
use vars qw(@ISA);
@ISA = qw(Geo::TAF::EN);
sub type { return __PACKAGE__; }

sub as_string
{
	my $self = shift;

	if($self->[1]) {
		return sprintf("until %s on the %s", $self->[0],$self->day($self->[1]));
	} else {
		return sprintf("until %s", $self->[0]);
	}
}

package Geo::TAF::EN::AT;
use vars qw(@ISA);
@ISA = qw(Geo::TAF::EN);
sub type { return __PACKAGE__; }

sub as_string
{
	my $self = shift;

	if($self->[1]) {
		return sprintf("at %s on the %s", $self->[0],$self->day($self->[1]));
	} else {
		return sprintf("at %s", $self->[0]);
	}
}

package Geo::TAF::EN::RMK;
use vars qw(@ISA);
@ISA = qw(Geo::TAF::EN);
sub type { return __PACKAGE__; }

sub as_string
{
	my $self = shift;

	return sprintf("remark %s", $self->[0]);
}

package Geo::TAF::EN::IGNORE;
use vars qw(@ISA);
@ISA = qw(Geo::TAF::EN);
sub type { return __PACKAGE__; }

sub as_string
{
	my $self = shift;
	return '';
}

package Geo::TAF::EN::BLOCK;
=pod
=begin classdoc

The 'BLOCK' marker is used to explicitly indicate a new block. If producing
human-readable output, this signifies that new line should be started.

@return nothing

=end classdoc
=cut
use vars qw(@ISA);
@ISA = qw(Geo::TAF::EN);
sub type { return __PACKAGE__; }

sub as_string
{
	my $self = shift;
	return '';
}

# Autoload methods go after =cut, and are processed by the autosplit program.

1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

Geo::TAF - Decode METAR and TAF strings

=head1 SYNOPSIS

  use strict;
  use Geo::TAF;

  my $t = new Geo::TAF;

  $t->metar("EGSH 311420Z 29010KT 1600 SHSN SCT004 BKN006 01/M00 Q1021");
  or
  $t->taf("EGSH 311205Z 311322 04010KT 9999 SCT020
     TEMPO 1319 3000 SHSN BKN008 PROB30
     TEMPO 1318 0700 +SHSN VV///
     BECMG 1619 22005KT");
  or 
  $t->decode("METAR EGSH 311420Z 29010KT 1600 SHSN SCT004 BKN006 01/M00 Q1021");
  or
  $t->decode("TAF EGSH 311205Z 311322 04010KT 9999 SCT020
     TEMPO 1319 3000 SHSN BKN008 PROB30
     TEMPO 1318 0700 +SHSN VV///
     BECMG 1619 22005KT");

  foreach my $c ($t->chunks) {
	  print $c->as_string, ' ';
  }
  or
  print $self->as_string;

  foreach my $c ($t->chunks) {
	  print $c->as_chunk, ' ';
  }
  or 
  print $self->as_chunk_string;

  my @out = $self->as_strings;
  my @out = $self->as_chunk_strings;
  my $line = $self->raw;
  print Geo::TAF::is_weather($line) ? 1 : 0;

=head1 ABSTRACT

Geo::TAF decodes aviation METAR and TAF weather forecast code 
strings into English or, if you sub-class, some other language.

=head1 DESCRIPTION

METAR (Routine Aviation weather Report) and TAF (Terminal Area
weather Report) are ascii strings containing codes describing
the weather at airports and weather bureaus around the world.

This module attempts to decode these reports into a form of 
English that is hopefully more understandable than the reports
themselves. 

It is possible to sub-class the translation routines to enable
translation to other langauages. 

=head1 METHODS

=over

=item new(%args)

Constructor for the class. Each weather announcement will need
a new constructor. 

If you sub-class the built-in English translation routines then 
you can pick this up by called the constructor thus:-

  my $t = Geo::TAF->new(chunk_package => 'Geo::TAF::ES');

or whatever takes your fancy.

=item decode($line)

The main routine that decodes a weather string. It expects a
string that begins with either the word C<METAR> or C<TAF>.
It creates a decoded form of the weather string in the object.

There are a number of fixed fields created and also array
of chunks L<chunks()> of (as default) C<Geo::TAF::EN>.

You can decode these manually or use one of the built-in routines.

This method returns undef if it is successful, a number otherwise.
You can use L<errorp($r)> routine to get a stringified
version. 

=item metar($line)

This simply adds C<METAR> to the front of the string and calls
L<decode()>.

=item taf($line)

This simply adds C<TAF> to the front of the string and calls
L<decode()>.

It makes very little difference to the decoding process which
of these routines you use. It does, however, affect the output
in that it will mark it as the appropriate type of report.

=item as_string()

Returns the decoded weather report as a human readable string.

This is probably the simplest and most likely of the output
options that you might want to use. See also L<as_strings()>.

=item as_strings()

Returns an array of strings without separators. This simply
the decoded, human readable, normalised strings presented
as an array.

=item as_chunk_string()

Returns a human readable version of the internal decoded,
normalised form of the weather report. 

This may be useful if you are doing something special, but
see L<chunks()> or L<as_chunk_strings()> for a procedural 
approach to accessing the internals.  

Although you can read the result, it is not, officially,
human readable.

=item as_chunk_strings()

Returns an array of the stringified versions of the internal
normalised form without separators.. This simply
the decoded (English as default) normalised strings presented
as an array.

=item chunks()

Returns a list of (as default) C<Geo::TAF::EN> objects. You 
can use C<$c-E<gt>as_string> or C<$c-E<gt>as_chunk> to 
translate the internal form into something readable. There
is also a routine (C<$c-E<gt>day>)to turn a day number into 
things like "1st", "2nd" and "24th". 

If you replace the English versions of these objects then you 
will need at an L<as_string()> method.

=item raw()

Returns the (cleaned up) weather report. It is cleaned up in the
sense that all whitespace is reduced to exactly one space 
character.

=item errorp($r)

Returns a stringified version of any error returned by L<decode()>

=back

=head1 ACCESSORS

=over

=item taf()

Returns whether this object is a TAF or not.

=item icao()

Returns the ICAO code contained in the weather report

=item day()

Returns the day of the month of this report

=item time()

Returns the issue time of this report

=item valid_day()

Returns the day this report is valid for (if there is one).

=item valid_from()

Returns the time from which this report is valid for (if there is one).

=item valid_to()

Returns the time to which this report is valid for (if there is one).

=item viz_dist()

Returns the minimum visibility, if present.

=item viz_units()

Returns the units of the visibility information.

=item wind_dir()

Returns the wind direction in degrees, if present.

=item wind_speed()

Returns the wind speed.

=item wind_units()

Returns the units of wind_speed.

=item wind_gusting()

Returns any wind gust speed. It is possible to have L<wind_speed()> 
without gust information.

=item pressure()

Returns the QNH (altimeter setting atmospheric pressure), if present.

=item pressure_units()

Returns the units in which L<pressure()> is messured.

=item temp()

Returns any temperature present.

=item dewpoint()

Returns any dewpoint present.

=back

=head1 ROUTINES

=over

=item is_weather($line)

This is a routine that determines, fairly losely, whether the
passed string is likely to be a weather report;

This routine is not exported. You must call it explicitly.

=back

=head1 SEE ALSO

L<Geo::METAR>

For a example of a weather forecast from the Norwich Weather 
Centre (EGSH) see L<http://www.tobit.co.uk>

For data see L<ftp://weather.noaa.gov/data/observations/metar/>
L<ftp://weather.noaa.gov/data/forecasts/taf/> and also
L<ftp://weather.noaa.gov/data/forecasts/shorttaf/>

To find an ICAO code for your local airport see
L<http://www.ar-group.com/icaoiata.htm>

=head1 AUTHOR

Dirk Koopman, L<mailto:djk@tobit.co.uk>
With additions/corrections by Robin H. Johnson, L<mailto:robbat2@gentoo.org>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2003 by Dirk Koopman, G1TLH
Portions Copyright (C) 2009 Robin H. Johnson

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut
