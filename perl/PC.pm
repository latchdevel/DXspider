#
# OO version of all the PC protocol stuff
#
# Here is done all reception, validation and generation of PC
# protocol frames
#
# This uses the Prot class as a basis for all 
# protocol entities
#

package PC10;

@ISA = qw(Prot);
use DXUtil;

use strict;

sub new
{
	my $pkg = shift;
	my $self = SUPER->new($pkg);
	$self->{from} = shift;
	$self->{to} = shift;     # is TO if {to} is blank
	$self->{text} = shift;
    $self->{flag} = shift;
    my $auxto = shift;
    $self->{origin} = shift;

	# sort out the to/via dillema and do some validation
	if (is_callsign($auxto)) {
		$self->{via} = $self->{to};
		$self->{to} = $auxto;
		return undef unless is_callsign($self->{via});
	}
	return undef unless is_callsign($self->{from}) && is_callsign($self->{to}) && is_callsign($self->{origin}) && is_pctext($self->{text}) && is_pcflag($self->{flag});
	return $self;
}

sub out {
	my $self = shift;
	my $addra = $self->{via} || $self->{to};
    my $addrb = exists $self->{via} ? $self->{to} : ' ';
	return "PC10^$self->{from}^$addra^$self->{text}^$self->{flag}^$addrb^$self->{origin}^~";
}

1;
__END__
