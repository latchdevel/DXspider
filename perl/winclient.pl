#!/usr/bin/perl -w
# The rudimentary beginnings of a Spider client which is known to run on ActiveState
# Perl under Win32
#
# It's very scrappy, but it *does* do enough to allow SysOp console access. It also
# means that since it's perl, Dirk might pretty it up a bit :-)
#
# $Id$
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

# Fork one in / one out .....
my $childpid;
die "can't fork: $!" unless defined($childpid = fork());

# the communication .....
if ($childpid) {
	STDOUT->autoflush(1);
    while (defined (my $msg = <$handle>)) {
		my ($sort, $call, $line) = $msg =~ /^(\w)([^\|]+)\|(.*)$/;
		if ($sort eq 'Z') {
			kill 'TERM', $childpid;
		} elsif ($sort eq 'E' || $sort eq 'B') {
			;
		} else {
			# newline ends all lines except a prompt
			my $end = "\n";
			if ($line =~ /^$call de $mycall\s+\d+-\w\w\w-\d+\s+\d+Z >$/) {
				$end = ' ';
			}
			print $line . $end;
		}
    }
    kill 'TERM', $childpid;
} else {
	$handle->autoflush(1);
	print $handle "A$call|local\n";
    while (defined (my $line = <STDIN>)) {
        print $handle "I$call|$line\n";
    }
}

exit 0;

