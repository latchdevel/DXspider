#
# set list of bad nodes
#
# Copyright (c) 1998 - Dirk Koopman G1TLH
#
# $Id$
#
my ($self, $line) = @_;
return (1, $self->msg('e5')) if $self->priv < 6;
my @f = split /\s+/, $line;
my @out;
for (@f) {
	my $call = uc $_;
	push @DXProt::nodx_node, $call;
	push @out, "$call is now a badnode";
}
return (1, @out);
