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
	return (1, $self->msg('e19')) if /[^\s\w_\-\/]/;
	my $call = uc $_;
	push @DXProt::nodx_node, $call;
	push @out, $self->msg('badnode1', $call);
}
return (1, @out);
