#
# display the band data
#

#$DB::single = 1;

my ($self, $line) = @_;
my @f = split /\s+/, $line;
my @bands;
my $band;
my @out;

if (!$line) {
  @bands = sort { Bands::get($a)->band->[0] <=> Bands::get($b)->band->[0] } Bands::get_keys();
  push @out, "Bands Available:-";
  foreach $band (@bands) {
    my $ref = Bands::get($band)->band;
    my $from = $ref->[0];
    my $to = $ref->[1];
    push @out, sprintf "%10s: %d -> %d", $band, $from, $to;
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
