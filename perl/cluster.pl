#!/usr/bin/perl
#
# This is the DX cluster 'daemon'. It sits in the middle of its little
# web of client routines sucking and blowing data where it may.
#
# Hence the name of 'spider' (although it may become 'dxspider')
#
# Copyright (c) 1998 Dirk Koopman G1TLH
#
# $Id$
# 

# make sure that modules are searched in the order local then perl
BEGIN {
  unshift @INC, '/spider/perl';  # this IS the right way round!
  unshift @INC, '/spider/local';
}

use Msg;
use DXVars;
use DXUtil;
use DXChannel;
use DXUser;
use DXM;
use DXCommandmode;
use DXProt;
use DXCluster;
use DXDebug;
use Prefix;
use Bands;

package main;

@inqueue = ();                # the main input queue, an array of hashes
$systime = 0;                 # the time now (in seconds)

# handle disconnections
sub disconnect
{
  my $dxchan = shift;
  return if !defined $dxchan;
  my $user = $dxchan->{user};
  my $conn = $dxchan->{conn};
  $dxchan->finish();
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
  
  # set up the basic channel info - this needs a bit more thought - there is duplication here
  if (!defined $dxchan) {
     my ($sort, $call, $line) = $msg =~ /^(\w)(\S+)\|(.*)$/;

     # is there one already connected?
	 if (DXChannel->get($call)) {
	   my $mess = DXM::msg('conother', $call);
	   dbg('chan', "-> D $call $mess\n"); 
       $conn->send_now("D$call|$mess");
	   sleep(1);
	   dbg('chan', "-> Z $call bye\n");
       $conn->send_now("Z$call|bye");          # this will cause 'client' to disconnect
	   return;
     }

	 # is there one already connected elsewhere in the cluster?
	 if (DXCluster->get($call)) {
	   my $mess = DXM::msg('concluster', $call);
	   dbg('chan', "-> D $call $mess\n"); 
       $conn->send_now("D$call|$mess");
	   sleep(1);
	   dbg('chan', "-> Z $call bye\n");
       $conn->send_now("Z$call|bye");          # this will cause 'client' to disconnect
	   return;
     }

     my $user = DXUser->get($call);
	 if (!defined $user) {
	   $user = DXUser->new($call);
	 }

     # create the channel
     $dxchan = DXCommandmode->new($call, $conn, $user) if ($user->sort eq 'U');
     $dxchan = DXProt->new($call, $conn, $user) if ($user->sort eq 'A');
	 die "Invalid sort of user on $call = $sort" if !$dxchan;
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
  exit(0);
}

# this is where the input queue is dealt with and things are dispatched off to other parts of
# the cluster
sub process_inqueue
{
  my $self = shift @inqueue;
  return if !$self;
  
  my $data = $self->{data};
  my $dxchan = $self->{dxchan};
  my ($sort, $call, $line) = $data =~ /^(\w)(\S+)\|(.*)$/;
  
  # do the really sexy console interface bit! (Who is going to do the TK interface then?)
  dbg('chan', "<- $sort $call $line\n");
  
  # handle A records
  my $user = $dxchan->user;
  if ($sort eq 'A') {
    $dxchan->start($line);  
  } elsif ($sort eq 'D') {
    die "\$user not defined for $call" if !defined $user;
	$dxchan->normal($line);  
    disconnect($dxchan) if ($dxchan->{state} eq 'bye');
  } elsif ($sort eq 'Z') {
    disconnect($dxchan);
  } else {
    print STDERR atime, " Unknown command letter ($sort) received from $call\n";
  }
}

#############################################################
#
# The start of the main line of code 
#
#############################################################

# open the debug file, set various FHs to be unbuffered
dbginit($debugfn);
foreach(@debug) {
  dbgadd($_);
}
STDOUT->autoflush(1);

# load Prefixes
print "loading prefixes ...\n";
Prefix::load();

# load band data
print "loading band data ...\n";
Bands::load();

# initialise User file system
print "loading user file system ...\n"; 
DXUser->init($userfn);

# start listening for incoming messages/connects
print "starting listener ...\n";
Msg->new_server("$clusteraddr", $clusterport, \&login);

# prime some signals
$SIG{'INT'} = \&cease;
$SIG{'TERM'} = \&cease;
$SIG{'HUP'} = 'IGNORE';

# initialise the protocol engine
DXProt->init();

# put in a DXCluster node for us here so we can add users and take them away
DXNode->new(0, $mycall, 0, 1, $DXProtvars::myprot_version); 

# this, such as it is, is the main loop!
print "orft we jolly well go ...\n";
for (;;) {
  my $timenow;
  Msg->event_loop(1, 0.001);
  $timenow = time;
  process_inqueue();                 # read in lines from the input queue and despatch them

  # do timed stuff, ongoing processing happens one a second
  if ($timenow != $systime) {
    $systime = $timenow;
	$cldate = &cldate();
	$ztime = &ztime();
    DXCommandmode::process();     # process ongoing command mode stuff
    DXProt::process();              # process ongoing ak1a pcxx stuff
  }
}

