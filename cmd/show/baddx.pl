#
# show list of bad dx callsigns
#
# Copyright (c) 1998 - Dirk Koopman G1TLH
#
# $Id$
#
my ($self, $line) = @_;
return $DXProt::baddx->show(1, $self);

