#!/usr/bin/perl -w
#
# A text message handling demon
#
# Copyright (c) 1997 Dirk Koopman G1TLH
#
# $Id$
#
# $Log$
# Revision 1.1  1997-11-26 00:55:39  djk
# initial version
#
#

require 5.003;
use Socket;
use FileHandle;
use Carp;

$mycall = "GB7DJK";
$listenport = 5072;

#
# system variables
#

$version = "1";
@port = ();     # the list of active ports (filehandle, $name, $sort, $device, $port, $ibufp, $ibuf, $obufp, $obuf, $prog)
@msg = ();      # the list of messages


#
# stop everything and exit
#
sub terminate
{
   print "closing spiderd\n";
   exit(0);
}

#
# start the tcp listener
#
sub startlisten
{
   my $proto = getprotobyname('tcp');
   my $h = new FileHandle;
   
   socket($h, PF_INET, SOCK_STREAM, $proto)               or die "Can't open listener socket: $!";
   setsockopt($h, SOL_SOCKET, SO_REUSEADDR, pack("l", 1)) or die "Can't set SO_REUSEADDR: $!";
   bind($h, sockaddr_in($listenport, INADDR_ANY))         or die "Can't bind listener socket: $!";
   listen($h, SOMAXCONN)                                  or die "Error on listen: $!";
   push @port, [ $h, "Listener", "listen", "localhost", $listenport, 0, "", 0, "", "spider" ];
   print "listening on port $listenport\n";
}

#
# close a tcp connection
#
sub close_con
{
   my ($p) = @_;
   close($port[$p][0]);
   print "closing ", $port[$p][3], $port[$p][4];
   splice @port, $p, 1;    # remove it from the list
   my $n = @port;
   print ", there are $n connections\n";
}

#
# the main select loop for incoming data
#
sub doselect
{
   my $rin = "";
   my $i;
   my $r; 
   my $h;
   my $maxport = 0;
   
   # set up the bit mask(s)
   for $i (0 .. $#port) {
      $h = fileno($port[$i][0]);
      vec($rin, $h, 1) = 1;
	  $maxport = $h if $h > $maxport;
   }
   
   $r = select($rin, undef, undef, 0.001);
   die "Error $! during select" if ($r < 0);
   if ($r > 0) {
#       print "input $r handles\n";
       for $i (0 .. $#port) {
           $h = $port[$i][0];
	       if (vec($rin, fileno($h), 1)) {     # we have some input!
		       my $sort = $port[$i][2];
			   
			   if ($sort eq "listen") {
			       my @entry;
				   my $ch = new FileHandle;
				   my $paddr = accept($ch, $h);
				   my ($port, $iaddr) = sockaddr_in($paddr);
				   my $name = gethostbyaddr($iaddr, AF_INET);
				   my $dotquad = inet_ntoa($iaddr);
				   my @rec = ( $ch, "unknown", "tcp", $name, $port, 0, "", 0, "", "unknown" );
				    
				   push @port, [ @rec ];    # add a new entry to be selected on
				   my $n = @port;
				   print "new connection from $name ($dotquad) port: $port, there are $n connections\n";
				   my $hello = join('|', ("HELLO",$mycall,"spiderd",$version)) . "\n";
				   $ch->autoflush(1);
				   print $ch $hello;
			   } else {
		           my $buf;
				   $r = sysread($h, $buf, 128);
				   if ($r == 0) {          # close the filehandle and remove it from the list of ports
				       close_con($i);
					   last;               # return, 'cos we will get the array subscripts in a muddle
				   } elsif ($r > 0) {
				       # we have a buffer full, search for a terminating character, cut it out
					   # and add it to the saved buffer, write the saved buffer away to the message
					   # list
					   $buf =~ /^(.*)[\r\n]+$/s;
					   if ($buf =~ /[\r\n]+$/) {
					       $buf =~ s/[\r\n]+$//;
					       push @msg, [ $i, $port[$i][6] . $buf ];
						   $port[$i][6] = "";
					   } else {
					       $port[$i][6] .= $buf;
					   }
				   }
			   }
		   }
	   }
   } 
}

#
# process each message on the queue
#

sub processmsg
{
   return if @msg == 0;
   
   my $list = shift @msg;
   my ($p, $msg) = @$list;
   my @m = split /\|/, $msg;
   my $hand = $port[$p][0];
   print "msg (port $p) = ", join(':', @m), "\n";
   
   # handle basic cases
   $m[0] = uc $m[0];
   
   if ($m[0] eq "QUIT" || $m[0] eq "BYE") {
       close_con($p);
	   return;
   }
   if ($m[0] eq "HELLO") {      # HELLO|<call>|<prog>|<version>
       $port[$p][1] = uc $m[1] if $m[1];
	   $port[$p][9] = $m[2] if $m[2];
	   print uc $m[1], " has just joined the message switch\n";
	   return;
   }
   if ($m[0] eq "CONFIG") {
       my $i;
	   for $i ( 0 .. $#port ) {
	       my ($h, $call, $sort, $addr, $pt) = @{$port[$i]};
		   my $p = join('|', ("CONFIG",$mycall,$i,$call,$sort,$addr,$pt,$port[$i][9])) . "\n";
		   print $hand $p;
	   }
	   return;
   }
}


#
# the main loop, this impliments the select which drives the whole thing round
#
sub main
{
   for (;;) {
       doselect;
       processmsg;
   }
}

#
# main program
#

$SIG{TERM} = \&terminate;
$SIG{INT} = \&terminate;

startlisten;
main;

