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

BEGIN {
  unshift @INC, "/spider/local";
  unshift @INC, "/spider/perl";
}

use Msg;
use DXVars;

$mode = 1;                      # 1 - \n = \r as EOL, 2 - \n = \n, 0 - transparent
$call = "";                     # the callsign being used
@stdoutq = ();                  # the queue of stuff to send out to the user
$conn = 0;                      # the connection object for the cluster
$lastbit = "";                  # the last bit of an incomplete input line

# cease communications
sub cease
{
  my $sendz = shift;
  if (defined $conn && $sendz) {
    $conn->send_now("Z$call|bye...\n");
  }
  exit(0);	
}

# terminate program from signal
sub sig_term
{
  cease(1);
}

sub setmode
{
  if ($mode == 1) {
    $nl = "\r";
  } else {
	$nl = "\n";
  }
  $/ = $nl;
  if ($mode == 0) {
    $\ = undef;
  } else {
    $\ = $nl;
  }
}

# handle incoming messages
sub rec_socket
{
  my ($con, $msg, $err) = @_;
  if (defined $err && $err) {
    cease(1);
  }
  if (defined $msg) {
    my ($sort, $call, $line) = $msg =~ /^(\w)(\S+)\|(.*)$/;
	
	if ($sort eq 'D') {
	   $nl = "" if $mode == 0;
	   $line =~ s/\n/\r/og if $mode == 1;
	   print $line;
	} elsif ($sort eq 'M') {
	  $mode = $line;               # set new mode from cluster
      setmode();
    } elsif ($sort eq 'Z') {       # end, disconnect, go, away .....
	  cease(0);
    }	  
  } 
}

sub rec_stdin
{
  my ($fh) = @_;
  my $buf;
  my @lines;
  my $r;
  my $first;
  my $dangle = 0;
  
  $r = sysread($fh, $buf, 1024);
#  print "sys: $r $buf";
  if ($r > 0) {
    if ($mode) {
	  $buf =~ s/\r/\n/og if $mode == 1;
	  $dangle = !($buf =~ /\n$/);
	  @lines = split /\n/, $buf;
	  if ($dangle) {                # pull off any dangly bits
	    $buf = pop @lines;
	  } else {
	    $buf = "";
	  }
	  $first = shift @lines;
	  unshift @lines, ($lastbit . $first) if ($first);
	  foreach $first (@lines) {
	    $conn->send_now("D$call|$first");
	  }
	  $lastbit = $buf;  
	} else {
	  $conn->send_now("D$call|$buf");
	}
  } elsif ($r == 0) {
    cease(1);
  }
}

$call = uc $ARGV[0];
die "client.pl <call> [<mode>]\r\n" if (!$call);
$mode = $ARGV[1] if (@ARGV > 1);
setmode();


#select STDOUT; $| = 1;
STDOUT->autoflush(1);

$SIG{'INT'} = \&sig_term;
$SIG{'TERM'} = \&sig_term;
$SIG{'HUP'} = \&sig_term;

$conn = Msg->connect("$clusteraddr", $clusterport, \&rec_socket);
$conn->send_now("A$call|start");
Msg->set_event_handler(\*STDIN, "read" => \&rec_stdin);
Msg->event_loop();

