#!/usr/bin/perl -w
#
# this is the operators console.
#
# Calling syntax is:-
#
# console.pl [callsign] 
#
# if the callsign isn't given then the sysop callsign in DXVars.pm is assumed
#
# Copyright (c) 1999 Dirk Koopman G1TLH
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
use IO::File;
use Curses;

use Carp qw{cluck};

# cease communications
sub cease
{
	my $sendz = shift;
	if ($conn && $sendz) {
		$conn->send_now("Z$call|bye...\n");
	}
	endwin();
	dbgclose();
#	$SIG{__WARN__} = sub {my $a = shift; cluck($a); };
	sleep(1);
	exit(0);	
}

# terminate program from signal
sub sig_term
{
	cease(1);
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
			$top->addstr("$line\n");
		} elsif ($sort eq 'Z') { # end, disconnect, go, away .....
			cease(0);
		}	  
	}
	$lasttime = time; 
}

sub rec_stdin
{
	my ($fh) = @_;

	$r = $bot->getch();
	
	#  my $prbuf;
	#  $prbuf = $buf;
	#  $prbuf =~ s/\r/\\r/;
	#  $prbuf =~ s/\n/\\n/;
	#  print "sys: $r ($prbuf)\n";
	if (defined $r) {
		if ($r eq "\n" || $r eq "\r") {
			$inbuf = " " unless $inbuf;
			$conn->send_later("I|$call|$inbuf");
			$inbuf = "";
		} else {
			$inbuf .= $r;
		}
	} 
	$bot->refresh();
}


#
# initialisation
#

$call = "";                     # the callsign being used
$conn = 0;                      # the connection object for the cluster
$lasttime = time;               # lasttime something happened on the interface

$connsort = "local";

#
# deal with args
#

$call = uc shift @ARGV if @ARGV;
$call = uc $myalias if !$call;

if ($call eq $mycall) {
	print "You cannot connect as your cluster callsign ($mycall)\n";
	exit(0);
}

$conn = Msg->connect("$clusteraddr", $clusterport, \&rec_socket);
if (! $conn) {
	if (-r "$data/offline") {
		open IN, "$data/offline" or die;
		while (<IN>) {
			print $_;
		}
		close IN;
	} else {
		print "Sorry, the cluster $mycall is currently off-line\n";
	}
	exit(0);
}


$SIG{'INT'} = \&sig_term;
$SIG{'TERM'} = \&sig_term;
$SIG{'HUP'} = 'IGNORE';

$scr = new Curses;
cbreak();
$top = $scr->subwin(LINES()-4, COLS, 0, 0);
$top->intrflush(0);
$top->scrollok(1);
$scr->addstr(LINES()-4, 0, '-' x COLS);
$bot = $scr->subwin(3, COLS, LINES()-3, 0);
$bot->intrflush(0);
$bot->scrollok(1);
$bot->keypad(1);
$scr->refresh();

$pages = LINES()-6;

$conn->send_now("A$call|$connsort");
$conn->send_now("I|$call|set/page $pages");
$conn->send_now("I|$call|set/nobeep");

Msg->set_event_handler(\*STDIN, "read" => \&rec_stdin);

for (;;) {
	my $t;
	Msg->event_loop(1, 0.010);
	$top->refresh() if $top->is_wintouched;
	$bot->refresh();
	$t = time;
	if ($t > $lasttime) {
		$lasttime = $t;
	}
}

exit(0);
