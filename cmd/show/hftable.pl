#
# do an HFSpot table 
#
# Copyright (c) 2001 Dirk Koopman G1TLH
#
# $Id$
#

my ($self, $line) = @_;
my @f = split /\s+/, $line;
my @calls;
my $days = 31;
my @dxcc;

push @dxcc, (61..67) if $self->dxcc >= 61 && $self->dxcc < 67;
push @dxcc, $self->dxcc unless @dxcc;

my $now = Julian::Day->new(time())->sub(1);
my %list;
my $i;

# generate the spot list
for ($i = 0; $i < $days; $i++) {
	my $fh = $Spot::statp->open($now); # get the next file
	unless ($fh) {
		Spot::genstats($now);
		$fh = $Spot::statp->open($now);
	}
	while (<$fh>) {
		chomp;
		my @l = split /\^/;
		next if $l[0] eq 'TOTALS';
		next unless grep $l[2] eq $_, @dxcc;
		my $ref = $list{$l[0]} || [0,0,0,0,0,0,0,0,0,0];
		my $j = 1;
		foreach my $item (@l[3..11]) {
			$ref->[$j] += $item;
			$ref->[0] += $item;
			$j++;
		}
		$list{$l[0]} = $ref if $ref->[0];
	}
	$now = $now->sub(1);
}

my @out;
my @tot;
my $nocalls;

push @out, $self->msg('stathft', join(',', @dxcc));
push @out, sprintf "%10s|%4s|%4s|%4s|%4s|%4s|%4s|%4s|%4s|%4s|%4s|", qw(Callsign Tot 160m 80m 40m 30m 20m 17m 15m 12m 10m);

for (sort {$list{$b}->[0] <=> $list{$a}->[0] || $a cmp $b} keys %list) {
	my $ref = $list{$_};
	$nocalls++;
	my @list = (sprintf "%10s", $_);
	foreach my $j (0..10) {
		my $r = $ref->[$j];
		if ($r) {
			$tot[$j] += $r;
			$r = sprintf("%4d", $r);
		} else {
			$r = '    ';
		}
		push @list, $r;
	}
	push @out, join('|', @list);
}

$nocalls = sprintf "%10s", "$nocalls calls";
@tot = map {$_ ?  sprintf("%4d", $_) : '    ' } @tot;
push @out, join('|', $nocalls, @tot, "");

return (1, @out);
