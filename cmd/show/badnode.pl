#
# show list of bad dx nodes
#
# Copyright (c) 1998 - Dirk Koopman G1TLH
#
#
#
my ($self, $line) = @_;
return $DXProt::badnode->show(1, $self);

