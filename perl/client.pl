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

# search local then perl directories
BEGIN {
  unshift @INC, "/spider/perl";   # this IS the right way round!
  unshift @INC, "/spider/local";
}

use Msg;
use DXVars;

$mode = 2;                      # 1 - \n = \r as EOL, 2 - \n = \n, 0 - transparent
$call = "";                     # the callsign being used
@stdoutq = ();                  # the queue of stuff to send out to the user
$conn = 0;                      # the connection object for the cluster
$lastbit = "";                  # the last bit of an incomplete input line
$mynl = "\n";                   # standard terminator
$lasttime = time;               # lasttime something happened on the interface
$outqueue = "";                 # the output queue length
$buffered = 1;                  # buffer output
$savenl = "";                   # an NL that has been saved from last time

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
    $mynl = "\r";
  } else {
	$mynl = "\n";
  }
  $/ = $mynl;
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
	   my $snl = $mynl;
	   my $newsavenl = "";
	   $snl = "" if $mode == 0;
	   if ($mode && $line =~ />$/) {
	     $newsavenl = $snl;
		 $snl = ' ';
	   }
	   $line =~ s/\n/\r/og if $mode == 1;
	   #my $p = qq($line$snl);
	   if ($buffered) {
	     if (length $outqueue >= 128) {
	       print $outqueue;
		   $outqueue = "";
	     }
	     $outqueue .= "$savenl$line$snl";
		 $lasttime = time;
	   } else {
	     print $savenl, $line, $snl;;
	   }
	   $savenl = $newsavenl;
	} elsif ($sort eq 'M') {
	  $mode = $line;               # set new mode from cluster
      setmode();
	} elsif ($sort eq 'B') {
	  if ($buffered && $outqueue) {
	    print $outqueue;
		$outqueue = "";
	  }
	  $buffered = $line;           # set buffered or unbuffered
    } elsif ($sort eq 'Z') {       # end, disconnect, go, away .....
	  cease(0);
    }	  
  }
  $lasttime = time; 
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
	  $savenl = "";     # reset savenl 'cos we will have done a newline on input
	} else {
	  $conn->send_now("D$call|$buf");
	}
  } elsif ($r == 0) {
    cease(1);
  }
  $lasttime = time;
}

$call = uc shift @ARGV;
$call = uc $mycall if !$call; 
$connsort = lc shift @ARGV;
$connsort = 'local' if !$connsort;
$mode = ($connsort =~ /^ax/o) ? 1 : 2;
setmode();

#select STDOUT; $| = 1;
STDOUT->autoflush(1);

$SIG{'INT'} = \&sig_term;
$SIG{'TERM'} = \&sig_term;
$SIG{'HUP'} = \&sig_term;

$conn = Msg->connect("$clusteraddr", $clusterport, \&rec_socket);
$conn->send_now("A$call|$connsort");
Msg->set_event_handler(\*STDIN, "read" => \&rec_stdin);

for (;;) {
  my $t;
  Msg->event_loop(1, 0.010);
  $t = time;
  if ($t > $lasttime) {
    if ($outqueue) {
	  print $outqueue;
	  $outqueue = "";
	}
	$lasttime = $t;
  }
}

