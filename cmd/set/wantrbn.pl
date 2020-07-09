#
# set the want rbn (at all)
#
# Copyright (c) 2020 - Dirk Koopman
#
#
#

my ($self, $line) = @_;
my @args = split /\s+/, uc $line;
my $call;
my @out;

my @calls;
my @want;

dbg('set/skimmer @args = "' . join(', ', @args) . '"') if isdbg('set/skim');

while (@args) {
	my $a = shift @args;
	dbg("set/skimmer \$a = $a") if isdbg('set/skim');;
	if ($a !~ /^(?:FT|BCN|BEA|DXF|CW|PSK|MSK|FSK|RTT|NO)/ && is_callsign($a)) {
		return (1, $self->msg('e5')) if $a ne $self->call	&& $self->priv < 9;
		push @calls, $a;
		next;
	}
	last unless $a;

	dbg("set/skimmer \$a = $a") if isdbg('set/skim');;

	my ($want) = $a =~ /^(FT|BCN|BEA|DXF|CW|PSK|MSK|FSK|RTT|NO)/;
	return (1, $self->msg('e39', $a)) unless $want;
	push @want, $want;
}

dbg('set/skimmer @calls = "' . join(', ', @calls) . '"') if isdbg('set/skim');
dbg('set/skimmer @want = "' . join(', ', @want) . '"') if isdbg('set/skim');

my $s = '';

push @calls, $self->call unless @calls;

foreach $call (@calls) {
	$call = uc $call;
	my $user = DXUser::get_current($call);
	if ($user) {

		dbg(sprintf("set/skimmer before rbn:%d ft:%d bcn:%d cw:%d psk:%d rtty:%d",
					$user->wantrbn,
					$user->wantft,
					$user->wantbeacon,
					$user->wantcw,
					$user->wantpsk,
					$user->wantrtty,
				   )) if isdbg('set/skim');
		
		$user->wantrbn(1);
		if (@want) {
			$user->wantft(0);
			$user->wantbeacon(0);
			$user->wantcw(0);
			$user->wantpsk(0);
			$user->wantrtty(0);
			for (@want) {
				$user->wantrbn(0) if /^NO/;
				$user->wantft(1) if /^FT/;
				$user->wantbeacon(1) if /^BCN|BEA|DXF/;
				$user->wantcw(1) if /^CW/;
				$user->wantpsk(1) if /^PSK|MSK|FSK/;
				$user->wantrtty(1) if /^RT/;
			}
		} elsif ($user->wantrbn) {
			$user->wantft(1);
			$user->wantbeacon(1);
			$user->wantcw(1);
			$user->wantpsk(1);
			$user->wantrtty(1);
		} else {
			$user->wantft(0);
			$user->wantbeacon(0);
			$user->wantcw(0);
			$user->wantpsk(0);
			$user->wantrtty(0);
		}

		dbg(sprintf("set/skimmer after rbn:%d ft:%d bcn:%d cw:%d psk:%d rtty:%d",
					$user->wantrbn,
					$user->wantft,
					$user->wantbeacon,
					$user->wantcw,
					$user->wantpsk,
					$user->wantrtty,
				   )) if isdbg('set/skim');
		
		my $s = '';
		if (@want) {
			@want = ();			# variable reuse!!
			push @want, 'CW' if $user->wantcw;
			push @want, 'BEACONS' if $user->wantbeacon;
			push @want, 'PSK, FSK' if $user->wantpsk;
			push @want, 'RTTY' if $user->wantrtty;
			push @want, 'FT8 & FT4' if $user->wantft;
		    $s = join(', ', @want) if @want && $user->wantrbn;
		} 
		
		dbg("set/skimmer \$s = $s") if isdbg('set/skim');;
		dbg('set/skimmer @want NOW = "' . join(', ', @want) . '"') if isdbg('set/skim');
		
		$s ||= $user->wantrbn ? 'ALL MODES' : 'NONE';
		$user->put;
		push @out, $self->msg('skims', $call, $s);
	}
	else {
		push @out, $self->msg('e3', "Set Skimmer", $call);
	}
}
return (1, @out);
