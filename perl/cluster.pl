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

package main;

@inqueue = undef;                # the main input queue, an array of hashes 

# handle out going messages
sub send_now
{
  my ($conn, $sort, $call, $line) = @_;

  print DEBUG "$t > $sort $call $line\n" if defined DEBUG;
  print "> $sort $call $line\n";
  $conn->send_now("$sort$call|$line");
}

sub send_later
{
  my ($conn, $sort, $call, $line) = @_;

  print DEBUG "$t > $sort $call $line\n" if defined DEBUG;
  print "> $sort $call $line\n";
  $conn->send_later("$sort$call|$line");
}

# handle disconnections
sub disconnect
{
  my $dxconn = shift;
  my ($user) = $dxconn->{user};
  my ($conn) = $dxconn->{conn};
  $user->close() if defined $user;
  $conn->disconnect();
  $dxconn->del();
}

# handle incoming messages
sub rec
{
  my ($conn, $msg, $err) = @_;
  my $dxconn = DXChannel->get_by_cnum($conn);      # get the dxconnnect object for this message
  
  if (defined $err && $err) {
    disconnect($dxconn);
	return;
  } 
  if (defined $msg) {
    my $self = bless {}, "inqueue";
    $self->{dxconn} = $dxconn;
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
  my $dxconn;
  foreach $dxconn (DXChannel->get_all()) {
    disconnect($dxconn);
  }
}

# this is where the input queue is dealt with and things are dispatched off to other parts of
# the cluster
sub process_inqueue
{
  my $self = shift @inqueue;
  return if !$self;
  
  my $data = $self->{data};
  my $dxconn = $self->{dxconn};
  my ($sort, $call, $line) = $data =~ /^(\w)(\S+)|(.*)$/;
  
  # do the really sexy console interface bit! (Who is going to do the TK interface then?)
  print DEBUG atime, " < $sort $call $line\n" if defined DEBUG;
  print "< $sort $call $line\n";
  
  # handle A records
  if ($sort eq 'A') {
    if ($dxconn) {                         # there should not be one of these, disconnect

	}
    my $user = DXUser->get($call);         # see if we have one of these
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

