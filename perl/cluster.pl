#!/usr/bin/perl
#
# A thing that implements dxcluster 'protocol'
#
# This is a perl module/program that sits on the end of a dxcluster
# 'protocol' connection and deals with anything that might come along.
#
# this program is called by ax25d and gets raw ax25 text on its input
#
# Copyright (c) 1998 Dirk Koopman G1TLH
#
# $Id$
# 

use Msg;
use DXVars;
use DXUtil;
use DXChannel;
use DXUser;
use DXM;

package main;

@inqueue = ();                # the main input queue, an array of hashes 

# handle disconnections
sub disconnect
{
  my $dxchan = shift;
  return if !defined $dxchan;
  my ($user) = $dxchan->{user};
  my ($conn) = $dxchan->{conn};
  $user->close() if defined $user;
  $conn->disconnect() if defined $conn;
  $dxchan->del();
}

# handle incoming messages
sub rec
{
  my ($conn, $msg, $err) = @_;
  my $dxchan = DXChannel->get_by_cnum($conn);      # get the dxconnnect object for this message
  
  if (defined $err && $err) {
    disconnect($dxchan) if defined $dxchan;
	return;
  }
  
  # set up the basic channel info
  if (!defined $dxchan) {
     my $user = DXUser->get($call);
	 $user = DXUser->new($call) if !defined $user;
     $dxchan = DXChannel->new($call, $conn, $user);  
  }
  
  # queue the message and the channel object for later processing
  if (defined $msg) {
    my $self = bless {}, "inqueue";
    $self->{dxchan} = $dxchan;
    $self->{data} = $msg;
	push @inqueue, $self;
  }
}

sub login
{
  return \&rec;
}

# cease running this program, close down all the connections nicely
sub cease
{
  my $dxchan;
  foreach $dxchan (DXChannel->get_all()) {
    disconnect($dxchan);
  }
}

# this is where the input queue is dealt with and things are dispatched off to other parts of
# the cluster
sub process_inqueue
{
  my $self = shift @inqueue;
  return if !$self;
  
  my $data = $self->{data};
  my $dxchan = $self->{dxchan};
  my ($sort, $call, $line) = $data =~ /^(\w)(\S+)|(.*)$/;
  
  # do the really sexy console interface bit! (Who is going to do the TK interface then?)
  print DEBUG atime, " < $sort $call $line\n" if defined DEBUG;
  print "< $sort $call $line\n";
  
  # handle A records
  if ($sort eq 'A') {
    my $user = $dxchan->{user};
	$user->{sort} = 'U' if !defined $user->{sort};
    if ($user->{sort} eq 'U') {
	  $dxchan->send_later('D', m('l2', $call, $mycall, $myqth));
	  $dxchan->send_file($motd) if (-e $motd);
	}
  } elsif (sort eq 'D') {
    ;
  } elsif ($sort eq 'Z') {
    disconnect($dxchan);
  }
}

#############################################################
#
# The start of the main line of code 
#
#############################################################

# open the debug file, set various FHs to be unbuffered
open(DEBUG, ">>$debugfn") or die "can't open $debugfn($!)\n";
select DEBUG; $| = 1;
select STDOUT; $| = 1;

# initialise User file system
DXUser->init($userfn);

# start listening for incoming messages/connects
Msg->new_server("$clusteraddr", $clusterport, \&login);

# prime some signals
$SIG{'INT'} = \&cease;
$SIG{'TERM'} = \&cease;
$SIG{'HUP'} = 'IGNORE';

# this, such as it is, is the main loop!
for (;;) {
  Msg->event_loop(1, 0.001);
  process_inqueue();
}

