#
# ping command
#
# Copyright (c) 1998 Dirk Koopman G1TLH
#
# $Id$
#

my $self = shift;
my $line = uc shift;   # only one callsign allowed 
my ($call) = $line =~ /^\s*(\S+)/;

# are we permitted?
return (1, $self->msg('e5')) if $self->priv < 1;

# is there a call?
return (1, $self->msg('e6')) if !$call;

# is it me?
return (1, $self->msg('pinge1')) if $call eq $main::mycall;

# can we see it? Is it a node?
my $noderef = DXCluster->get_exact($call);
$noderef = DXChannel->get($call) unless $noderef;

return (1, $self->msg('e7', $call)) if !$noderef || !$noderef->pcversion;

# ping it
DXProt::addping($self->call, $call);

return (1, $self->msg('pingo', $call));


