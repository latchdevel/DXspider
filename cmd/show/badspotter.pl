#
# show list of bad spotter callsigns
#
# Copyright (c) 1998 - Dirk Koopman G1TLH
#
#
#
my ($self, $line) = @_;
return $DXProt::badspotter->show(1, $self);

