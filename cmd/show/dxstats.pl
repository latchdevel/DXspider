#
# Show total DXStats per day
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
my $tot;

push @out, $self->msg('statdx');
foreach my $ref (@in) {
	push @out, sprintf "%12s: %7d", $ref->[0]->as_string, $ref->[1];
	$tot += $ref->[1];
}
push @out, sprintf "%12s: %7d", "Total", $tot;

return (1, @out);
