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
use DXProtVars;
use DXCommandmode;

use strict;

#
# obtain a new connection this is derived from dxchannel
#

sub new 
{
  my $self = DXChannel::alloc(@_);
  $self->{sort} = 'A';   # in absence of how to find out what sort of an object I am
  return $self;
}

# this is how a pc connection starts (for an incoming connection)
# issue a PC38 followed by a PC18, then wait for a PC20 (remembering
# all the crap that comes between).
sub start
{
  my ($self, $line) = shift;
  my $call = $self->call;
  
  # remember type of connection
  $self->{consort} = $line;

  # set unbuffered
  $self->send_now('B',"0");
  
  # send initialisation string
  $self->send($self->pc38()) if DXNode->get_all();
  $self->send($self->pc18());
  $self->state('normal');
  $self->pc50_t(time);
}

#
# This is the normal pcxx despatcher
#
sub normal
{
  my ($self, $line) = @_;
  my @field = split /[\^\~]/, $line;
  
  # ignore any lines that don't start with PC
  return if !$field[0] =~ /^PC/;

  # process PC frames
  my ($pcno) = $field[0] =~ /^PC(\d\d)/;          # just get the number
  return if $pcno < 10 || $pcno > 51;
  
  SWITCH: {
    if ($pcno == 10) {last SWITCH;}
    if ($pcno == 11) {             # dx spot
	  
	  last SWITCH;
	}
    if ($pcno == 12) {last SWITCH;}
    if ($pcno == 13) {last SWITCH;}
    if ($pcno == 14) {last SWITCH;}
    if ($pcno == 15) {last SWITCH;}
    if ($pcno == 16) {last SWITCH;}
    if ($pcno == 17) {last SWITCH;}
    if ($pcno == 18) {last SWITCH;}
    if ($pcno == 19) {last SWITCH;}
    if ($pcno == 20) {              # send local configuration

      # set our data (manually 'cos we only have a psuedo channel [at the moment])
	  my $hops = $self->get_hops();
	  $self->send("PC19^1^$main::mycall^0^$DXProt::myprot_version^$hops^");
	  
      # get all the local users and send them out
      my @list;
	  for (@list = DXCommandmode::get_all(); @list; ) {
	    @list = $self->pc16(@list);
	    my $out = shift @list;
		$self->send($out);
	  }
	  $self->send($self->pc22());
	  return;
	}
    if ($pcno == 21) {             # delete a cluster from the list
	  
	  last SWITCH;
	}
    if ($pcno == 22) {last SWITCH;}
    if ($pcno == 23) {last SWITCH;}
    if ($pcno == 24) {last SWITCH;}
    if ($pcno == 25) {last SWITCH;}
    if ($pcno == 26) {last SWITCH;}
    if ($pcno == 27) {last SWITCH;}
    if ($pcno == 28) {last SWITCH;}
    if ($pcno == 29) {last SWITCH;}
    if ($pcno == 30) {last SWITCH;}
    if ($pcno == 31) {last SWITCH;}
    if ($pcno == 32) {last SWITCH;}
    if ($pcno == 33) {last SWITCH;}
    if ($pcno == 34) {last SWITCH;}
    if ($pcno == 35) {last SWITCH;}
    if ($pcno == 36) {last SWITCH;}
    if ($pcno == 37) {last SWITCH;}
    if ($pcno == 38) {last SWITCH;}
    if ($pcno == 39) {last SWITCH;}
    if ($pcno == 40) {last SWITCH;}
    if ($pcno == 41) {last SWITCH;}
    if ($pcno == 42) {last SWITCH;}
    if ($pcno == 43) {last SWITCH;}
    if ($pcno == 44) {last SWITCH;}
    if ($pcno == 45) {last SWITCH;}
    if ($pcno == 46) {last SWITCH;}
    if ($pcno == 47) {last SWITCH;}
    if ($pcno == 48) {last SWITCH;}
    if ($pcno == 49) {last SWITCH;}
    if ($pcno == 50) {
	  last SWITCH;
	}
    if ($pcno == 51) {              # incoming ping requests/answers
	  
	  # is it for us?
	  if ($field[1] eq $main::mycall) {
	    my $flag = $field[3];
	    $flag ^= 1;
	    $self->send($self->pc51($field[2], $field[1], $flag));
	  } else {
	    # route down an appropriate thingy
		$self->route($field[1], $line);
	  }
	  return;
	}
  }
  
  # if get here then rebroadcast the thing with its Hop count decremented (if
  # the is one). If it has a hop count and it decrements to zero then don't
  # rebroadcast it.
  #
  # NOTE - don't arrive here UNLESS YOU WANT this lump of protocol to be
  #        REBROADCAST!!!!
  #
  
  my $hopfield = pop @field;
  push @field, $hopfield; 
  
  my $hops;
  if (($hops) = $hopfield =~ /H(\d+)\^\~?$/o) {
	my $newhops = $hops - 1;
	if ($newhops > 0) {
	  $line =~ s/\^H$hops(\^\~?)$/\^H$newhops$1/;       # change the hop count
	  DXProt->broadcast($line, $self);             # send it to everyone but me
	}
  }
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
    next if !$chan->is_ak1a();

    # send a pc50 out on this channel
    if ($t >= $chan->pc50_t + $DXProt::pc50_interval) {
      $chan->send(pc50());
	  $chan->pc50_t($t);
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
# add a (local) user to the cluster
#

sub adduser
{

}

#
# delete a (local) user to the cluster
#

sub deluser
{

}

#
# add a (locally connected) node to the cluster
#

sub addnode
{

}

#
# delete a (locally connected) node to the cluster
#
sub delnode
{

}

#
# some active measures
#

#
# route a message down an appropriate interface for a callsign
#
# expects $self to indicate 'from' and is called $self->route(to, pcline);
#
sub route
{
  my ($self, $call, $line) = @_;
  my $cl = DXCluster->get($call);
  if ($cl) {
    my $dxchan = $cl->{dxchan};
    $cl->send($line) if $dxchan;
  }
}

# broadcast a message to all clusters [except those mentioned after buffer]
sub broadcast
{
  my $pkg = shift;                # ignored
  my $s = shift;                  # the line to be rebroadcast
  my @except = @_;                # to all channels EXCEPT these (dxchannel refs)
  my @chan = DXChannel->get_all();
  my ($chan, $except);
  
L: foreach $chan (@chan) {
     next if !$chan->sort eq 'A';  # only interested in ak1a channels  
	 foreach $except (@except) {
	   next L if $except == $chan;  # ignore channels in the 'except' list
	 }
	 chan->send($s);              # send it
  }
}

#
# gimme all the ak1a nodes
#
sub get_all
{
  my @list = DXChannel->get_all();
  my $ref;
  my @out;
  foreach $ref (@list) {
    push @out, $ref if $ref->sort eq 'A';
  }
  return @out;
}

#
# obtain the hops from the list for this callsign and pc no 
#

sub get_hops
{
  my ($self, $pcno) = @_;
  return "H$DXProt::def_hopcount";       # for now
}

#
# All the PCxx generation routines
#

#
# add one or more users (I am expecting references that have 'call', 
# 'confmode' & 'here' method) 
# 
# NOTE this sends back a list containing the PC string (first element)
# and the rest of the users not yet processed
# 
sub pc16
{
  my $self = shift;    
  my @list = @_;       # list of users
  my @out = ('PC16', $main::mycall);
  my $i;
  
  for ($i = 0; @list && $i < $DXProt::pc16_max_users; $i++) {
    my $ref = shift @list;
	my $call = $ref->call;
	my $s = sprintf "%s %s %d", $call, $ref->confmode ? '*' : '-', $ref->here;
	push @out, $s;
  }
  push @out, $self->get_hops();
  my $str = join '^', @out;
  $str .= '^';
  return ($str, @list);
}

# Request init string
sub pc18
{
  return "PC18^wot a load of twaddle^$DXProt::myprot_version^~";
}

#
# add one or more nodes 
# 
# NOTE this sends back a list containing the PC string (first element)
# and the rest of the nodes not yet processed (as PC16)
# 
sub pc19
{
  my $self = shift;    
  my @list = @_;       # list of users
  my @out = ('PC19', $main::mycall);
  my $i;
  
  for ($i = 0; @list && $i < $DXProt::pc19_max_nodes; $i++) {
    my $ref = shift @list;
	push @out, $ref->here, $ref->call, $ref->confmode, $ref->pcversion;
  }
  push @out, $self->get_hops();
  my $str = join '^', @out;
  $str .= '^';
  return ($str, @list);
}

# end of Rinit phase
sub pc20
{
  return 'PC20^';
}

# delete a node
sub pc21
{
  my ($self, $ref, $reason) = @_;
  my $call = $ref->call;
  my $hops = $self->get_hops();
  return "PC21^$call^$reason^$hops^";
}

# end of init phase
sub pc22
{
  return 'PC22^';
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

# periodic update of users, plus keep link alive device (always H99)
sub pc50
{
  my $n = DXNodeuser->count;
  return "PC50^$main::mycall^$n^H99^";
}

# generate pings
sub pc51
{
  my ($self, $to, $from, $val) = @_;
  return "PC51^$to^$from^$val^";
}
1;
__END__ 
