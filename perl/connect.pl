#!/usr/bin/perl
#
# connect to an external entity
#
# This is the routine that is called by the cluster to manage
# an outgoing connection to the point where it is 'connected'.
# From there the client program is forked and execed over the top of
# this program and that connects back to the cluster as though
# it were an incoming connection.
#
# Essentially this porgram does the same as chat in that there
# are 'expect', 'send' pairs of strings. The 'expect' string is 
# a pattern. You can include timeout and abort string statements
# at any time.
#
# Commands are:-
#
# connect <type> <destination>|<program>
# timeout <secs>
# abort <regexp>
# client <client name> <parameters>
# '<regexp>' '<send string>'
#
# Copyright (c) Dirk Koopman G1TLH
#
# $Id$
#

# search local then perl directories
BEGIN {
	# root of directory tree for this system
	$root = "/spider"; 
	$root = $ENV{'DXSPIDER_ROOT'} if $ENV{'DXSPIDER_ROOT'};
	
	unshift @INC, "$root/perl";	# this IS the right way round!
	unshift @INC, "$root/local";
}

use DXVars;
use IO::Socket;
use IO::File;
use Open2;
use DXDebug;
use POSIX qw(dup);
use Carp;

$timeout = 30;					# default timeout for each stage of the connect
$abort = '';					# default connection abort string
$path = "$root/connect";		# the basic connect directory
$client = "$root/perl/client.pl"; # default client

$connected = 0;					# we have successfully connected or started an interface program
$pid = 0;                       # the pid of the child program
$csort = "";                    # the connection type
$sock = 0;                      # connection socket

sub timeout;
sub term;
sub reap;

$SIG{ALRM} = \&timeout;
$SIG{TERM} = \&term;
$SIG{INT} = \&term;
$SIG{REAP} = \&reap;
$SIG{HUP} = 'IGNORE';

exit(1) if !$ARGV[0];			# bang out if no callsign
open(IN, "$path/$ARGV[0]") or exit(2);
@in = <IN>;
close IN;
STDOUT->autoflush(1);
dbgadd('connect');

alarm($timeout);

for (@in) {
	chomp;
	next if /^\s*\#/o;
	next if /^\s*$/o;
	doconnect($1, $2) if /^\s*co\w*\s+(\w+)\s+(.*)$/io;
	doclient($1) if /^\s*cl\w*\s+(\w+)\s+(.*)$/io;
	doabort($1) if /^\s*a\w*\s+(.*)/io;
	dotimeout($1) if /^\s*t\w*\s+(\d+)/io;
	dochat($1, $2) if /\s*\'(.*)\'\s+\'(.*)\'/io;          
}

sub doconnect
{
	my ($sort, $line) = @_;
	dbg('connect', "CONNECT sort: $sort command: $line");
	if ($sort eq 'net') {
		# this is a straight network connect
		my ($host) = $line =~ /host\s+(\w+)/o;
		my ($port) = $line =~ /port\s+(\d+)/o;
		$port = 23 if !$port;
		
		$sock = IO::Socket::INET->new(PeerAddr => "$host", PeerPort => "$port", Proto => 'tcp')
			or die "Can't connect to $host port $port $!";
		
	} elsif ($sort eq 'ax25') {
		my @args = split /\s+/, $line;
		$pid = open2(\*R, \*W, "$line") or die "can't do $line $!";
		dbg('connect', "got pid $pid");
		W->autoflush(1);
	} else {
		die "can't get here";
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
	alarm($timeout = $val);
}

sub dochat
{
	my ($expect, $send) = @_;
	dbg('connect', "CHAT \"$expect\" -> \"$send\"");
    my $line;

	alarm($timeout);
	
    if ($expect) {
		if ($csort eq 'net') {
			$line = <$sock>;
			chomp;
		} elsif ($csort eq 'ax25') {
			local $/ = "\r";
			$line = <R>;
			$line =~ s/\r//og;
		}
		dbg('connect', "received \"$line\"");
		if ($abort && $line =~ /$abort/i) {
			dbg('connect', "aborted on /$abort/");
			exit(11);
		}
	}
	if ($send && (!$expect || $line =~ /$expect/i)) {
		if ($csort eq 'net') {
			$sock->print("$send\n");
		} elsif ($csort eq 'ax25') {
			local $\ = "\r";
			W->print("$send\r");
		}
		dbg('connect', "sent \"$send\"");
	}
}

sub doclient
{
	my ($cl, $args) = @_;
	dbg('connect', "client: $cl args: $args");
    my @args = split /\s+/, $args;

#	if (!defined ($pid = fork())) {
#		dbg('connect', "can't fork");
#		exit(13);
#	}
#	if ($pid) {
#		sleep(1);
#		exit(0);
#	} else {
		
		close(STDIN);
		close(STDOUT);
		if ($csort eq 'net') {
			open STDIN, "<&$sock";
			open STDOUT, ">&$sock";
			exec $cl, @args;
		} elsif ($csort eq 'ax25') {
			open STDIN, "<&R";
			open STDOUT, ">&W";
			exec $cl, @args;
		} else {
			dbg('connect', "client can't get here");
			exit(13);
		}
#    }
}

sub timeout
{
	dbg('connect', "timed out after $timeout seconds");
	exit(10);
}

sub term
{
	dbg('connect', "caught INT or TERM signal");
	kill $pid if $pid;
	sleep(2);
	exit(12);
}

sub reap
{
    my $wpid = wait;
	dbg('connect', "pid $wpid has died");
}
