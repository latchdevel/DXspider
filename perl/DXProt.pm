#!/usr/bin/perl
#
# This module impliments the protocal mode for a dx cluster
#
# Copyright (c) 1998 Dirk Koopman G1TLH
#
# $Id$
# 

package DXProt;

@ISA = qw(DXChannel);

use DXUtil;
use DXChannel;
use DXUser;
use DXM;
use DXCluster;

# this is how a pc connection starts (for an incoming connection)
# issue a PC38 followed by a PC18, then wait for a PC20 (remembering
# all the crap that comes between).
sub start
{
  my $self = shift;
  my $call = $self->call;
  
  # do we have him connected on the cluster somewhere else?
  if (DXCluster->get
  $self->pc38();
  $self->pc18();
  $self->{state} = 'incoming';
}

#
# This is the normal pcxx despatcher
#
sub normal
{

}

#
# This is called from inside the main cluster processing loop and is used
# for despatching commands that are doing some long processing job
#
sub process
{

}

#
# finish up a pc context
#
sub finish
{

}
 
#
# All the various PC routines
#

1;
__END__ 
