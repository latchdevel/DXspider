#
# set list of bad dx spotters
#
# Copyright (c) 1998 - Dirk Koopman G1TLH
#
# $Id$
#
my ($self, $line) = @_;
$line = join(' ', map {s|[/-]\d+$||; $_} split(/\s+/, $line));
return $DXProt::badspotter->unset(8, $self->msg('e6'), $self, $line);

