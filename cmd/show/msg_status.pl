#
# show msgs system status
#
# Copyright (c) 2000 Dirk Koopman G1TLH
#
# $Id$
#
my $self = shift;
return (0, $self->msg('e5')) if $self->priv < 5;

my @out;

push @out, "Work Queue";
for (keys %DXMsg::work) {
	push @out, "$_ : $DXMsg::work{$_}\n";
}
push @out, "Busy Queue";
for (keys %DXMsg::busy) {
	push @out, "$_ : $DXMsg::busy{$_}\n";
}
return (0, @out);
