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

use strict;

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
  
  # set the channel sort
  $self->sort('A');

  # set unbuffered
  self->send_now('B',"0");
  
  # do we have him connected on the cluster somewhere else?
  $self->send(pc38());
  $self->send(pc18());
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
  my $t = time;
  my @chan = DXChannel->get_all();
  my $chan;
  
  foreach $chan (@chan) {
    next if $chan->sort ne 'A';  

    # send a pc50 out on this channel
    if ($t >= $chan->t + $main::pc50_interval) {
      $chan->send(pc50());
	  $chan->t($t);
	}
  }
}

#
# finish up a pc context
#
sub finish
{

}
 
#
# some active measures
#

sub broadcast
{
  my $s = shift;
  $s = shift if ref $s;           # if I have been called $self-> ignore it.
  my @except = @_;                # to all channels EXCEPT these (dxchannel refs)
  my @chan = DXChannel->get_all();
  my ($chan, $except);
  
L: foreach $chan (@chan) {
     next if $chan->sort != 'A';  # only interested in ak1a channels  
	 foreach $except (@except) {
	   next L if $except == $chan;  # ignore channels in the 'except' list
	 }
	 chan->send($s);              # send it
  }
}

#
# All the PCxx generation routines
#

sub pc18
{
  return "PC18^wot a load of twaddle^$main::myprot_version^~";
}

# send all the DX clusters I reckon are connected
sub pc38
{
  my @list = DXNode->get_all();
  my $list;
  my @nodes;
  
  foreach $list (@list) {
    push @nodes, $list->call;
  }
  return "PC38^" . join(',', @nodes) . "^~";
}

sub pc50
{
  my $n = DXUsers->count;
  return "PC50^$main::mycall^$n^H99^";
}

1;
__END__ 
