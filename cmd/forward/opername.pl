#
# Cause node to send PC41 info frames
#
# Copyright (c) 1998 - Iain Philipps G0RDI
#
# Mods by Dirk Koopman G1TLH 12Dec98
#

my ($self, $line) = @_;
my @f = split /\s+/, uc $line;
my @out;

if ($self->priv < 1) {
	if (@f == 0) {
		push @f, $self->call;
	} else {
		return (1, $self->msg('e5'));
	}
} elsif (@f == 0) {
	return (1, $self->msg('e6'));
}

my $call;
foreach $call (@f) {
	my $ref = DXUser->get_current($call);
	if ($ref) {
		my $name = $ref->name;  
		my $qth = $ref->qth;
		my $lat = $ref->lat;
		my $long = $ref->long;
		my $node = $ref->homenode;
		my $latlong = DXBearing::lltos($lat, $long) if $lat && $long;
		DXProt::broadcast_all_ak1a(DXProt::pc41($call, 1, $name), $DXProt::me) if $name;
		DXProt::broadcast_all_ak1a(DXProt::pc41($call, 2, $qth), $DXProt::me) if $qth;
		DXProt::broadcast_all_ak1a(DXProt::pc41($call, 3, $latlong), $DXProt::me) if $latlong;
		DXProt::broadcast_all_ak1a(DXProt::pc41($call, 4, $node), $DXProt::me) if $node;
	}
}

return (1, @out);
