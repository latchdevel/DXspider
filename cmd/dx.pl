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
my $valid = 0;

# first lets see if we think we have a callsign as the first argument
if (defined @f && @f >= 3 && $f[0] =~ /[A-Za-z]/) {
	$spotter = uc $f[0];
	$freq = $f[1];
	$spotted = uc $f[2];
	$line =~ s/^$f[0]\s+$f[1]\s+$f[2]\s*//;
} elsif (defined @f && @f >= 2) {
	$freq = $f[0];
	$spotted = uc $f[1]; 
	$line =~ s/^$f[0]\s+$f[1]\s*//;
} elsif (!defined @f || @f < 2) {
	return (1, $self->msg('dx2'));
}

# bash down the list of bands until a valid one is reached
my $bandref;
my @bb;
my $i;

# first in KHz
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

if (!$valid) {

	# try again in MHZ 
	$freq = $freq * 1000 if $freq;

 L2:
    foreach $bandref (Bands::get_all()) {
		@bb = @{$bandref->band};
		for ($i = 0; $i < @bb; $i += 2) {
			if ($freq >= $bb[$i] && $freq <= $bb[$i+1]) {
				$valid = 1;
				last L2;
			}
		}
	}
}



push @out, $self->msg('dx1', $freq) if !$valid;

# check we have a callsign :-)
if ($spotted le ' ') {
	push @out, $self->msg('dx2');
	
	$valid = 0;
}

return (1, @out) if !$valid;

# change ^ into : for transmission
$line =~ s/\^/:/og;

# Store it here
if (Spot::add($freq, $spotted, $main::systime, $line, $spotter, $main::mycall)) {
	# send orf to the users
	my $buf = Spot::formatb($freq, $spotted, $main::systime, $line, $spotter);
	DXProt::broadcast_users($buf, 'dx', $buf);


	# send it orf to the cluster (hang onto your tin helmets)!
	DXProt::broadcast_ak1a(DXProt::pc11($spotter, $freq, $spotted, $line));
}

return (1, @out);
