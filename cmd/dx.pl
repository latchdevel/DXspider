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
my @f = split /\s+/, $line, 3;
my $spotter = $self->call;
my $spotted;
my $freq;
my @out;
my $valid = 0;

# do we have at least two args?
return (1, $self->msg('dx2')) unless @f >= 2;

# as a result of a suggestion by Steve K9AN, I am changing the syntax of
# 'spotted by' things to "dx by g1tlh <freq> <call>" <freq> and <call>
# can be in any order

if ($f[0] =~ /^by$/i) {
    $spotter = uc $f[1];
    $line =~ s/^\s*$f[0]\s+$f[1]\s+//;
	$line = $f[2];
	@f = split /\s+/, $line;
	return (1, $self->msg('dx2')) unless @f >= 2;
}

# get the freq and callsign either way round
if ($f[0] =~ /[A-Za-z]/) {
	$spotted = uc $f[0];
	$freq = $f[1];
} elsif ($f[0] =~ /^[0-9\.\,]+$/) {
    $freq = $f[0];
	$spotted = uc $f[1];
} else {
	return (1, $self->msg('dx2'));
}

# make line the rest of the line
$line = $f[2] || " ";
@f = split /\s+/, $line;

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

unless ($valid) {

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


push @out, $self->msg('dx1', $freq) unless $valid;

# check we have a callsign :-)
if ($spotted le ' ') {
	push @out, $self->msg('dx2');
	
	$valid = 0;
}

return (1, @out) unless $valid;

# change ^ into : for transmission
$line =~ s/\^/:/og;

# Store it here (but only if it isn't baddx)
if (grep $_ eq $spotted, @DXProt::baddx) {
	my $buf = Spot::formatb($freq, $spotted, $main::systime, $line, $spotter);
	push @out, $buf;
} else {
	my @spot = Spot::add($freq, $spotted, $main::systime, $line, $spotter, $main::mycall);
	if (@spot) {
		# send orf to the users
		DXProt::send_dx_spot($self, DXProt::pc11($spotter, $freq, $spotted, $line), @spot);
	}
}

return (1, @out);
