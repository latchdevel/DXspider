#
# Show total HF DX Spot Stats per day
#
# Copyright (c) 2001 Dirk Koopman G1TLH
#
# $Id$
#

my ($self, $line) = @_;
my @f = split /\s+/, $line;
my $days = 31;
my $now = Julian::Day->new(time())->sub(31);
my $i;
my @in;

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
		next unless $l[0] eq 'TOTALS';
		next unless $l[1];
		$l[0] = $now; 
		push @in, \@l; 
		last;
	}
	$now = $now->add(1);
}

my @out;
my @tot;

push @out, $self->msg('stathf');
push @out, sprintf "%11s|%6s|%5s|%5s|%5s|%5s|%5s|%5s|%5s|%5s|%5s|", qw(Date Total 160m 80m 40m 30m 20m 17m 15m 12m 10m);
foreach my $ref (@in) {
	my $linetot = 0;
	foreach my $j (3..11) {
		$tot[$j] += $ref->[$j];
		$tot[0] += $ref->[$j];
		$linetot += $ref->[$j];
	}
	push @out, join '|', sprintf("%11s|%6d", $ref->[0]->as_string, $linetot), map {$_ ? sprintf("%5d", $_) : '     '} @$ref[3..11], "";
}
push @out, join '|', sprintf("%11s|%6d", 'Total', $tot[0]), map {$_ ? sprintf("%5d", $_) : '     '} @tot[3..11], "";

return (1, @out);
