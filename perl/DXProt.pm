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

# this is how a pc connection starts (for an incoming connection)
# issue a PC38 followed by a PC18, then wait for a PC20 (remembering
# all the crap that comes between).
sub start
{
  my $self = shift;
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

1;
__END__ 
