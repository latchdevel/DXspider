#!/usr/bin/perl -w
#
# A thing that implements dxcluster 'protocol'
#
# This is a perl module/program that sits on the end of a dxcluster
# 'protocol' connection and deals with anything that might come along.
#
# this program is called by ax25d or inetd and gets raw ax25 text on its input
# It can also be launched into the ether by the cluster program itself for outgoing
# connections
#
# Calling syntax is:-
#
# client.pl [callsign] [telnet|ax25|local] [[connect] [program name and args ...]]
#
# if the callsign isn't given then the sysop callsign in DXVars.pm is assumed
#
# if there is no connection type then 'local' is assumed
#
# if there is a 'connect' keyword then it will try to launch the following program
# and any arguments and connect the stdin & stdout of both the program and the 
# client together.
#
# Copyright (c) 1998 Dirk Koopman G1TLH
#
# $Id$
# 

require 5.004;

# search local then perl directories
BEGIN {
	# root of directory tree for this system
	$root = "/spider"; 
	$root = $ENV{'DXSPIDER_ROOT'} if $ENV{'DXSPIDER_ROOT'};
	
	unshift @INC, "$root/perl";	# this IS the right way round!
	unshift @INC, "$root/local";
}

use Msg;
use DXVars;
use DXDebug;
use Net::Telnet qw(TELOPT_ECHO);
use IO::File;
use IO::Socket;
use IPC::Open2;
use Carp qw{cluck};

# cease communications
sub cease
{
	my $sendz = shift;
	if ($conn && $sendz) {
		$conn->send_now("Z$call|bye...\n");
		sleep(1);
	}
	$stdout->flush if $stdout;
	if ($pid) {
		dbg('connect', "killing $pid");
		kill(9, $pid);
	}
	dbgclose();
#	$SIG{__WARN__} = sub {my $a = shift; cluck($a); };
	sleep(1);

	# do we need this ?
	$conn->disconnect if $conn;
	exit(0);	
}

# terminate program from signal
sub sig_term
{
	cease(1);
}

# terminate a child
sub sig_chld
{
	$SIG{CHLD} = \&sig_chld;
	$waitedpid = wait;
	dbg('connect', "caught $pid");
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
		my ($sort, $call, $line) = $msg =~ /^(\w)([A-Z0-9\-]+)\|(.*)$/;
		
		if ($sort eq 'D') {
			my $snl = $mynl;
			my $newsavenl = "";
			$snl = "" if $mode == 0;
			if ($mode == 2 && $line =~ />$/) {
				$newsavenl = $snl;
				$snl = ' ';
			}
			$line =~ s/\n/\r/og if $mode == 1;
			#my $p = qq($line$snl);
			if ($buffered) {
				if (length $outqueue >= $client_buffer_lth) {
					print $stdout $outqueue;
					$outqueue = "";
				}
				$outqueue .= "$savenl$line$snl";
				$lasttime = time;
			} else {
				print $stdout $savenl, $line, $snl;;
			}
			$savenl = $newsavenl;
		} elsif ($sort eq 'M') {
			$mode = $line;		# set new mode from cluster
			setmode();
		} elsif ($sort eq 'E') {
			if ($sort eq 'telnet') {
				$mode = $line;		# set echo mode from cluster
				my $term = POSIX::Termios->new;
				$term->getattr(fileno($sock));
				$term->setiflag( 0 );
				$term->setoflag( 0 );
				$term->setattr(fileno($sock), &POSIX::TCSANOW );
			}
		} elsif ($sort eq 'I') {
			;                       # ignore echoed I frames
		} elsif ($sort eq 'B') {
			if ($buffered && $outqueue) {
				print $stdout $outqueue;
				$outqueue = "";
			}
			$buffered = $line;	# set buffered or unbuffered
		} elsif ($sort eq 'Z') { # end, disconnect, go, away .....
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
	#  my $prbuf;
	#  $prbuf = $buf;
	#  $prbuf =~ s/\r/\\r/;
	#  $prbuf =~ s/\n/\\n/;
	#  print "sys: $r ($prbuf)\n";
	if (!defined $r || $r == 0) {
		cease(1);
	} elsif ($r > 0) {
		if ($mode) {
			$buf =~ s/\r/\n/og if $mode == 1;
			$buf =~ s/\r\n/\n/og if $mode == 2;
			$dangle = !($buf =~ /\n$/);
			if ($buf eq "\n") {
				@lines = (" ");
			} else {
				@lines = split /\n/, $buf;
			}
			if ($dangle) {		# pull off any dangly bits
				$buf = pop @lines;
			} else {
				$buf = "";
			}
			$first = shift @lines;
			unshift @lines, ($lastbit . $first) if ($first);
			foreach $first (@lines) {
				#		  print "send_now $call $first\n";
				$conn->send_later("I$call|$first");
			}
			$lastbit = $buf;
			$savenl = "";		# reset savenl 'cos we will have done a newline on input
		} else {
			$conn->send_later("I$call|$buf");
		}
	} 
	$lasttime = time;
}

sub optioncb
{
}

sub doconnect
{
	my ($sort, $line) = @_;
	dbg('connect', "CONNECT sort: $sort command: $line");
	if ($sort eq 'telnet') {
		# this is a straight network connect
		my ($host, $port) = split /\s+/, $line;
		$port = 23 if !$port;
		
#		if ($port == 23) {

			$sock = new Net::Telnet (Timeout => $timeout, Port => $port);
			$sock->option_callback(\&optioncb);
			$sock->output_record_separator('');
#			$sock->option_log('option_log');
#			$sock->dump_log('dump');
			$sock->option_accept(Dont => TELOPT_ECHO, Wont => TELOPT_ECHO);
			$sock->open($host) or die "Can't connect to $host port $port $!";
#		} else {
#			$sock = IO::Socket::INET->new(PeerAddr => "$host:$port", Proto => 'tcp')
#				or die "Can't connect to $host port $port $!";
#		}
	} elsif ($sort eq 'ax25' || $sort eq 'prog') {
		my @args = split /\s+/, $line;
		$rfh = new IO::File;
		$wfh = new IO::File;
		$pid = open2($rfh, $wfh, "$line") or die "can't do $line $!";
		die "no receive channel $!" unless $rfh;
		die "no transmit channel $!" unless $wfh;
		dbg('connect', "got pid $pid");
		$wfh->autoflush(1);
	} else {
		die "invalid type of connection ($sort)";
	}
	$csort = $sort;
}

sub doabort
{
	my $string = shift;
	dbg('connect', "abort $string");
	$abort = $string;
}

sub dotimeout
{
	my $val = shift;
	dbg('connect', "timeout set to $val");
	$timeout = $val;
}

sub dochat
{
	my ($expect, $send) = @_;
	dbg('connect', "CHAT \"$expect\" -> \"$send\"");
    my $line;
	
	alarm($timeout);
	
    if ($expect) {
		for (;;) {
			if ($csort eq 'telnet') {
				$line = $sock->get();
				cease(11) unless $line;          # the socket has gone away?
				$line =~ s/\r\n/\n/og;
				chomp;
			} elsif ($csort eq 'ax25' || $csort eq 'prog') {
				local $/ = "\r";
				$line = <$rfh>;
				$line =~ s/\r//og;
			}
			if (length $line == 0) {
				dbg('connect', "received 0 length line, aborting...");
				cease(11);
			}
			dbg('connect', "received \"$line\"");
			if ($abort && $line =~ /$abort/i) {
				dbg('connect', "aborted on /$abort/");
				cease(11);
			}
			last if $line =~ /$expect/i;
		}
	}
	if ($send) {
		if ($csort eq 'telnet') {
			$sock->print("$send\n");
		} elsif ($csort eq 'ax25') {
			local $\ = "\r";
			$wfh->print("$send");
		}
		dbg('connect', "sent \"$send\"");
	}
}

sub timeout
{
	dbg('connect', "timed out after $timeout seconds");
	cease(0);
}


#
# initialisation
#

$mode = 2;                      # 1 - \n = \r as EOL, 2 - \n = \n, 0 - transparent
$call = "";                     # the callsign being used
$conn = 0;                      # the connection object for the cluster
$lastbit = "";                  # the last bit of an incomplete input line
$mynl = "\n";                   # standard terminator
$lasttime = time;               # lasttime something happened on the interface
$outqueue = "";                 # the output queue 
$client_buffer_lth = 200;       # how many characters are buffered up on outqueue
$buffered = 1;                  # buffer output
$savenl = "";                   # an NL that has been saved from last time
$timeout = 60;                  # default timeout for connects
$abort = "";                    # the current abort string
$cpath = "$root/connect";		# the basic connect directory

$pid = 0;                       # the pid of the child program
$csort = "";                    # the connection type
$sock = 0;                      # connection socket

$stdin = *STDIN;
$stdout = *STDOUT;
$rfh = 0;
$wfh = 0;

$waitedpid = 0;

#
# deal with args
#

$call = uc shift @ARGV if @ARGV;
$call = uc $myalias if !$call;
$connsort = lc shift @ARGV if @ARGV;
$connsort = 'local' if !$connsort;

$loginreq = $call eq 'LOGIN';

# we will do this again later 'cos things may have changed
$mode = ($connsort eq 'ax25') ? 1 : 2;
setmode();

if ($call eq $mycall) {
	print $stdout "You cannot connect as your cluster callsign ($mycall)", $nl;
	cease(0);
}

$stdout->autoflush(1);

$SIG{'INT'} = \&sig_term;
$SIG{'TERM'} = \&sig_term;
$SIG{'HUP'} = 'IGNORE';
$SIG{'CHLD'} = \&sig_chld;
$SIG{'ALRM'} = \&timeout;

dbgadd('connect');

# do we need to do a login and password job?
if ($loginreq) {
	my $user;
	my $s;

	if (-e "$data/issue") {
		open(I, "$data/issue") or die;
		local $/ = undef;
		$issue = <I>;
		close(I);
		$issue = s/\n/\r/og if $mode == 1;
		local $/ = $nl;
		$stdout->print($issue) if $issue;
	}
	

	use DXUser;
	
	DXUser->init($userfn);
	
	# allow a login from an existing user. I could create a user but
	# I want to check for valid callsigns and I don't have the 
	# necessary info / regular expression yet
	for ($state = 0; $state < 2; ) {
		alarm($timeout);
		
		if ($state == 0) {
			$stdout->print('login: ');
			$stdout->flush();
			local $\ = $nl;
			$s = $stdin->getline();
			chomp $s;
			$s =~ s/\s+//og;
			$s =~ s/-\d+$//o;            # no ssids!
			cease(0) unless $s gt ' ';
			$call = uc $s;
			$user = DXUser->get($call);
			$state = 1;
		} elsif ($state == 1) {
			$stdout->print('password: ');
			$stdout->flush();
			local $\ = $nl;
			$s = $stdin->getline();
			chomp $s;
			$state = 2;
			if (!$user || ($user->passwd && $user->passwd ne $s)) {
				$stdout->print("sorry...$nl");
				cease(0);
			}
		}
	}
}

# handle callsign and connection type firtling
sub doclient
{
	my $line = shift;
	my @f = split /\s+/, $line;
	$call = uc $f[0] if $f[0];
	$csort = $f[1] if $f[1];
}

# is this an out going connection?
if ($connsort eq "connect") {
	my $mcall = lc $call;
	
	open(IN, "$cpath/$mcall") or cease(2);
	@in = <IN>;
	close IN;

	alarm($timeout);
	
	for (@in) {
		chomp;
		next if /^\s*\#/o;
		next if /^\s*$/o;
		doconnect($1, $2) if /^\s*co\w*\s+(\w+)\s+(.*)$/io;
		doabort($1) if /^\s*a\w*\s+(.*)/io;
		dotimeout($1) if /^\s*t\w*\s+(\d+)/io;
		dochat($1, $2) if /\s*\'(.*)\'\s+\'(.*)\'/io;
		if (/\s*cl\w+\s+(.*)/io) {
			doclient($1);
			last;
		}
	}
	
    dbg('connect', "Connected to $call ($csort), starting normal protocol");
	dbgsub('connect');
	
	# if we get here we are connected
	if ($csort eq 'ax25' || $csort eq 'prog') {
		#		open(STDIN, "<&R"); 
		#		open(STDOUT, ">&W"); 
		#		close R;
		#		close W;
        $stdin = $rfh;
		$stdout = $wfh;
		$csort = 'telnet' if $csort eq 'prog';
	} elsif ($csort eq 'telnet') {
		#		open(STDIN, "<&$sock"); 
		#		open(STDOUT, ">&$sock"); 
		#		close $sock;
		$stdin = $sock;
		$stdout = $sock;
	}
    alarm(0);
    $outbound = 1;
	$connsort = $csort;
	$stdout->autoflush(1);
	close STDIN;
	close STDOUT;
	close STDERR;
}

$mode = ($connsort eq 'ax25') ? 1 : 2;
setmode();

$conn = Msg->connect("$clusteraddr", $clusterport, \&rec_socket);
if (! $conn) {
	if (-r "$data/offline") {
		open IN, "$data/offline" or die;
		while (<IN>) {
			s/\n/\r/og if $mode == 1;
			print $stdout $_;
		}
		close IN;
	} else {
		print $stdout "Sorry, the cluster $mycall is currently off-line", $mynl;
	}
	cease(0);
}

$let = $outbound ? 'O' : 'A';
$conn->send_now("$let$call|$connsort");
Msg->set_event_handler($stdin, "read" => \&rec_stdin);

for (;;) {
	my $t;
	Msg->event_loop(1, 1);
	$t = time;
	if ($t > $lasttime) {
		if ($outqueue) {
			print $stdout $outqueue;
			$outqueue = "";
		}
		$lasttime = $t;
	}
}

exit(0);
