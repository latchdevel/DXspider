#!/usr/bin/env perl
# The rudimentary beginnings of a Spider client which is known to run on ActiveState
# Perl under Win32
#
# It's very scrappy, but it *does* do enough to allow SysOp console access. It also
# means that since it's perl, Dirk might pretty it up a bit :-)
#
#
#
# Iain Philipps, G0RDI	03-Mar-01
#

require 5.004;

use strict;

# search local then perl directories
BEGIN {
	use vars qw($root $myalias $mycall $clusteraddr $clusterport $data);

	# root of directory tree for this system
	$root = "/spider"; 
	$root = $ENV{'DXSPIDER_ROOT'} if $ENV{'DXSPIDER_ROOT'};
	
	unshift @INC, "$root/perl";	# this IS the right way round!
	unshift @INC, "$root/local";
}

use IO::Socket;
use DXVars;
use IO::File;
use Config;

#
# deal with args
#

my $call = uc shift @ARGV if @ARGV;
$call = uc $myalias if !$call;
my ($scall, $ssid) = split /-/, $call;
$ssid = undef unless $ssid && $ssid =~ /^\d+$/;  
if ($ssid) {
	$ssid = 15 if $ssid > 15;
	$call = "$scall-$ssid";
}
if ($call eq $mycall) {
	print "You cannot connect as your cluster callsign ($mycall)\n";
	exit(0);
}

# connect to server
my $handle = IO::Socket::INET->new(Proto     => "tcp",
								   PeerAddr  => $clusteraddr,
								   PeerPort  => $clusterport);
unless ($handle) {
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

STDOUT->autoflush(1);
$handle->autoflush(1);
print $handle "A$call|local\n";

# Fork or thread one in / one out .....
my $childpid;
my $t;
if ($Config{usethreads}) {
	require Thread;
#	print "Using Thread Method\n";
	$t = Thread->new(\&dostdin);
	donetwork();
	$t->join;
	kill(-1, $$);
} else {
#	print "Using Fork Method\n";
	die "can't fork: $!" unless defined($childpid = fork());	
	if ($childpid) {
		donetwork();
		kill 'TERM', $childpid;
	} else {
		dostdin();
	}
}
exit 0;


sub donetwork
{
	my ($lastend, $end) = ("\n", "\n");
	
    while (defined (my $msg = <$handle>)) {
		my ($sort, $call, $line) = $msg =~ /^(\w)([^\|]+)\|(.*)$/;
		next unless defined $sort;
		$line =~ s/\%([0-9A-F][0-9A-F])/chr(hex($1))/eg;
		if ($sort eq 'Z') {
			return;
		} elsif ($sort eq 'E' || $sort eq 'B') {
			;
		} else {
			# newline ends all lines except a prompt
			$lastend = $end;
			$end = "\n";
			if ($line =~ /^$call de $mycall\s+\d+-\w\w\w-\d+\s+\d+Z >$/o) {
				$end = ' ';
			}
			my $begin = ($lastend eq "\n") ? '' : "\n";
			print $begin . $line . $end;
		}
    }
}

sub dostdin
{
    while (defined (my $line = <STDIN>)) {
        print $handle "I$call|$line\n";
		if ($t && ($line =~ /^b/i || $line =~ /^q/i)) {
			return;
		}
    }
}



