#
# show list of bad nodes
#
# Copyright (c) 1998 - Dirk Koopman G1TLH
#
# $Id$
#
my ($self, $line) = @_;
return (1, $self->msg('e5')) if $self->priv < 6;
my @out = ($self->msg('badnode3'));
for (@DXProt::nodx_node) {
	push @out,  $_;
}
return (1, @out);
