#
# accept/reject filter commands
#
# Copyright (c) 2000 Dirk Koopman G1TLH
#
# $Id$
#

my ($self, $line) = @_;
my $type = 'reject';
my $sort  = 'ann';

my ($r, $filter, $fno) = $Geomag::filterdef->cmd($self, $sort, $type, $line);
return (0, $r ? $r : $self->msg('filter1', $fno, $filter->{name})); 
