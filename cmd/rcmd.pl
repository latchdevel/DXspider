#
# rcmd command
#
# Copyright (c) 1998 Dirk Koopman G1TLH
#
# $Id$
#

my $self = shift;
my $line = shift; 
my ($call) = $line =~ /^\s*(\S+)/;

# are we permitted?
return (1, $self->msg('e5')) if $self->priv < 6;

# is there a call?
return (1, $self->msg('e6')) if !$call;

# remove the callsign from the line
$line =~ s/^\s*$call\s+//;

# can we see it? Is it a node?
$call = uc $call;
my $noderef = DXCluster->get_exact($call);
return (1, $self->msg('e7', $call)) if !$noderef || !$noderef->pcversion;

# ping it
DXProt::addrcmd($self->call, $call, $line);

return (1, $self->msg('rcmdo', $line, $call));
