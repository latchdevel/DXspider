#
# display the band data
#
# Copyright (c) 1998 - Dirk Koopman G1TLH
#
#
#

#$DB::single = 1;

my ($self, $line) = @_;
my @f = split /\s+/, $line;
my @bands;
my $band;
my @out;
my $i;

if (!$line) {
	@bands = sort { Bands::get($a)->band->[0] <=> Bands::get($b)->band->[0] } Bands::get_keys();
	push @out, "Bands Available:-";
	foreach $band (@bands) {
		my $ref = Bands::get($band)->band;
		my $s = sprintf "%10s: ", $band;
		for ($i = 0; $i < $#{$ref}; $i += 2) {
			my $from = $ref->[$i];
			my $to = $ref->[$i+1];
			$s .= ", " if $i;
			$s .= "$from -> $to";
		}
		push @out, $s;
	} 
	push @out, "Regions Available:-";
	@bands = Bands::get_region_keys();
	foreach $band (@bands) {
		my $ref = Bands::get_region($band);
		my $s = sprintf("%10s: ", $band ) . join(' ', @{$ref}); 
		push @out, $s;
	}
}

return (1, @out);
