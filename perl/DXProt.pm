#!/usr/bin/perl
#
# This module impliments the protocal mode for a dx cluster
#
# Copyright (c) 1998 Dirk Koopman G1TLH
#
# $Id$
# 

package DXProt;

use DXUtil;
use DXChannel;
use DXUser;
use DXM;

# this is how a pc connection starts (for an incoming connection)
# issue a PC38 followed by a PC18, then wait for a PC20 (remembering
# all the crap that comes between).
sub pc_start
{
  my $self = shift;
  $self->{normal} = \&pc_normal;
  $self->{finish} = \&pc_finish;
}

#
# This is the normal pcxx despatcher
#
sub pc_normal
{

}

#
# This is called from inside the main cluster processing loop and is used
# for despatching commands that are doing some long processing job
#
sub pc_process
{

}

#
# finish up a pc context
#
sub pc_clean
{

}

1;
__END__ 
