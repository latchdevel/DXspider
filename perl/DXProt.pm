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
use Spot;
use Date::Parse;
use DXProtout;

use strict;

my $me;            # the channel id for this cluster

sub init
{
  my $user = DXUser->get($main::mycall);
  $me = DXChannel::alloc('DXProt', $main::mycall, undef, $user); 
  $me->{sort} = 'M';    # M for me
}

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
  $self->send(pc38()) if DXNode->get_all();
  $self->send(pc18());
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
    if ($pcno == 10) {             # incoming talk

      # is it for me or one of mine?
	  my $call = ($field[5] gt ' ') ? $field[5] : $field[2];
	  if ($call eq $main::mycall || grep $_ eq $call, get_all_user_calls()) {
	    
		# yes, it is
		my $text = unpad($field[3]);
		my $ref = DXChannel->get($call);
		$ref->send("$call de $field[1]: $text") if $ref;
	  } else {
	    route($field[2], $line);       # relay it on its way
	  }
	  return;
	}
	
    if ($pcno == 11) {             # dx spot

      # if this is a 'nodx' node then ignore it
	  last SWITCH if grep $field[7] =~ /^$_/,  @DXProt::nodx_node;
	  
      # convert the date to a unix date
	  my $date = $field[3];
	  my $time = $field[4];
	  $date =~ s/^\s*(\d+)-(\w\w\w)-(19\d\d)$/$1 $2 $3/;
	  $time =~ s/^(\d\d)(\d\d)Z$/$1:$2 +0000/;
	  my $d = str2time("$date $time");
	  return if !$d;               # bang out (and don't pass on) if date is invalid
	  
	  # strip off the leading & trailing spaces from the comment
	  my $text = unpad($field[5]);
	  
	  # store it away
	  Spot::add($field[1], $field[2], $d, $text, $field[6]);
	  
	  # format and broadcast it to users
	  my $spotter = $field[6];
	  $spotter =~ s/^(\w+)-\d+/$1/;    # strip off the ssid from the spotter
      $spotter .= ':';                # add a colon
	  
	  # send orf to the users
	  my $buf = sprintf "DX de %-7.7s %13.13s %-12.12s %-30.30s %5.5s\a\a", $spotter, $field[1], $field[2], $text, $field[4];
      broadcast_users($buf);
	  
	  last SWITCH;
	}
	
    if ($pcno == 12) {             # announces
	
	  if ($field[2] eq '*' || $field[2] eq $main::mycall) {

        # strip leading and trailing stuff
	    my $text = unpad($field[3]);
		my $target = "To Sysops" if $field[4] eq '*';
		$target = "WX" if $field[6];
		$target = "To All" if !$target;
		broadcast_users("$target de $field[1]: $text"); 
		
		return if $field[2] eq $main::mycall;   # it's routed to me
	  } else {
	    route($field[2], $line);
		return;                     # only on a routed one
	  }
	  
	  last SWITCH;
	}
	
    if ($pcno == 13) {last SWITCH;}
    if ($pcno == 14) {last SWITCH;}
    if ($pcno == 15) {last SWITCH;}
	
    if ($pcno == 16) {              # add a user
	  my $node = DXCluster->get($field[1]);
	  last SWITCH if !$node;        # ignore if havn't seen a PC19 for this one yet
	  my $i;
	  
	  for ($i = 2; $i < $#field-1; $i++) {
	    my ($call, $confmode, $here) = $field[$i] =~ /^(\w+) (-) (\d)/o;
		next if length $call < 3;
		next if !$confmode;
        $call =~ s/^(\w+)-\d+/$1/;        # remove ssid
		next if DXCluster->get($call);    # we already have this (loop?)
		
		$confmode = $confmode eq '*';
		DXNodeuser->new($self, $node, $call, $confmode, $here);
	  }
	  last SWITCH;
	}
	
    if ($pcno == 17) {              # remove a user
	  my $ref = DXCluster->get($field[1]);
	  $ref->del() if $ref;
	  last SWITCH;
	}
	
    if ($pcno == 18) {              # link request
	
      # send our nodes
	  my $hops = get_hops(19);
	  $self->send($me->pc19(get_all_ak1a()));
	  
      # get all the local users and send them out
	  $self->send($me->pc16(get_all_users()));
	  $self->send(pc20());
	  last SWITCH;
	}
	
    if ($pcno == 19) {               # incoming cluster list
      my $i;
	  for ($i = 1; $i < $#field-1; $i += 4) {
	    my $here = $field[$i];
	    my $call = $field[$i+1];
		my $confmode = $field[$i+2] eq '*';
		my $ver = $field[$i+3];
		
		# now check the call over
		next if DXCluster->get($call);   # we already have this
		
		# check for sane parameters
		next if $ver < 5000;             # only works with version 5 software
		next if length $call < 3;        # min 3 letter callsigns
        DXNode->new($self, $call, $confmode, $here, $ver);
	  }
	  last SWITCH;
	}
	
    if ($pcno == 20) {              # send local configuration

      # send our nodes
	  my $hops = get_hops(19);
	  $self->send($me->pc19(get_all_ak1a()));
	  
      # get all the local users and send them out
	  $self->send($me->pc16(get_all_users()));
	  $self->send(pc22());
	  return;
	}
	
    if ($pcno == 21) {             # delete a cluster from the list
	  my $ref = DXCluster->get($field[1]);
	  $ref->del() if $ref;
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
	
    if ($pcno == 50) {              # keep alive/user list
	  my $ref = DXCluster->get($field[1]);
	  $ref->update_users($field[2]) if $ref;
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
		route($field[1], $line);
	  }
	  return;
	}
  }
  
  # if get here then rebroadcast the thing with its Hop count decremented (if
  # there is one). If it has a hop count and it decrements to zero then don't
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
	  broadcast_ak1a($line, $self);             # send it to everyone but me
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
  my $self = shift;
  broadcast_ak1a($self->pc21('Gone.'));
  $self->delnode();
}
 
# 
# add a (local) user to the cluster
#

sub adduser
{
  DXNodeuser->add(@_);
}

#
# delete a (local) user to the cluster
#

sub deluser
{
  my $self = shift;
  my $ref = DXCluster->get($self->call);
  $ref->del() if $ref;
}

#
# add a (locally connected) node to the cluster
#

sub addnode
{
  DXNode->new(@_);
}

#
# delete a (locally connected) node to the cluster
#
sub delnode
{
  my $self = shift;
  my $ref = DXCluster->get($self->call);
  $ref->del() if $ref;
}

#
# some active measures
#

#
# route a message down an appropriate interface for a callsign
#
# is called route(to, pcline);
#
sub route
{
  my ($call, $line) = @_;
  my $cl = DXCluster->get($call);
  if ($cl) {
    my $dxchan = $cl->{dxchan};
    $cl->send($line) if $dxchan;
  }
}

# broadcast a message to all clusters [except those mentioned after buffer]
sub broadcast_ak1a
{
  my $s = shift;                  # the line to be rebroadcast
  my @except = @_;                # to all channels EXCEPT these (dxchannel refs)
  my @chan = get_all_ak1a();
  my $chan;
  
  foreach $chan (@chan) {
	 $chan->send($s) if !grep $chan, @except;              # send it if it isn't the except list
  }
}

# broadcast to all users
sub broadcast_users
{
  my $s = shift;                  # the line to be rebroadcast
  my @except = @_;                # to all channels EXCEPT these (dxchannel refs)
  my @chan = get_all_users();
  my $chan;
  
  foreach $chan (@chan) {
	 $chan->send($s) if !grep $chan, @except;              # send it if it isn't the except list
  }
}

#
# gimme all the ak1a nodes
#
sub get_all_ak1a
{
  my @list = DXChannel->get_all();
  my $ref;
  my @out;
  foreach $ref (@list) {
    push @out, $ref if $ref->is_ak1a;
  }
  return @out;
}

# return a list of all users
sub get_all_users
{
  my @list = DXChannel->get_all();
  my $ref;
  my @out;
  foreach $ref (@list) {
    push @out, $ref if $ref->is_user;
  }
  return @out;
}

# return a list of all user callsigns
sub get_all_user_calls
{
  my @list = DXChannel->get_all();
  my $ref;
  my @out;
  foreach $ref (@list) {
    push @out, $ref->call if $ref->is_user;
  }
  return @out;
}

#
# obtain the hops from the list for this callsign and pc no 
#

sub get_hops
{
  my ($pcno) = @_;
  my $hops = $DXProt::hopcount{$pcno};
  $hops = $DXProt::def_hopcount if !$hops;
  return "H$hops";       
}

# remove leading and trailing spaces from an input string
sub unpad
{
  my $s = shift;
  $s =~ s/^\s+|\s+$//;
  return $s;
}
1;
__END__ 
