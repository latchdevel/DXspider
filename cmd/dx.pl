#
# the DX command
#
# this is where the fun starts!
#
# Copyright (c) 1998 Dirk Koopman G1TLH
#
# $Id$
#

my ($self, $line) = @_;
my @f = split /\s+/, $line;
my $spotter = $self->call;
my $spotted;
my $freq;
my @out;

# first lets see if we think we have a callsign as the first argument
if ($f[0] =~ /[A-Za-z]/) {
  $spotter = uc $f[0];
  $freq = $f[1];
  $spotted = $f[2];
  $line =~ s/^$f[0]\s+$freq\s+$spotted\s*//;
} else {
  $freq = $f[0];
  $spotted = $f[1]; 
  $line =~ s/^$f[0]\s+$f[1]\s*//;
}

# check the freq, if the number is < 1800 it is in Mhz (probably)
$freq = $freq * 1000 if $freq < 1800;

# bash down the list of bands until a valid one is reached
my $valid = 0;
my $bandref;
my @bb;
my $i;

L1:
foreach $bandref (Bands::get_all()) {
  @bb = @{$bandref->band};
  for ($i = 0; $i < @bb; $i += 2) {
    if ($freq >= $bb[$i] && $freq <= $bb[$i+1]) {
	  $valid = 1;
	  last L1;
	}
  }
}

push @out, "Frequency $freq not in band [usage: DX freq call comments]" if !$valid;
return (1, @out) if !$valid;

# send orf to the users
my $buf = sprintf "DX de %-7.7s %13.1f %-12.12s %-30.30s %5.5s\a\a", $spotter, $freq, $spotted, $line, ztime(time);
DXProt::broadcast_users($buf);

# Store it here
Spot::add($freq, $spotted, time, $line, $spotter);

# send it orf to the cluster (hang onto your tin helmets)!
DXProt::broadcast_ak1a(DXProt::pc11($spotter, $freq, $spotted, $line));

return (1, @out);
