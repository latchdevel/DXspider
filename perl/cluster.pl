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
	# root of directory tree for this system
	$root = "/spider"; 
	$root = $ENV{'DXSPIDER_ROOT'} if $ENV{'DXSPIDER_ROOT'};
	
	unshift @INC, "$root/perl";	# this IS the right way round!
	unshift @INC, "$root/local";

#	require Exporter;
#	$Exporter::Verbose = 1;
}

use Msg;
use DXVars;
use DXDebug;
use DXLog;
use DXUtil;
use DXChannel;
use DXUser;
use DXM;
use DXCommandmode;
use DXProt;
use DXMsg;
use DXCluster;
use DXCron;
use DXConnect;
use Prefix;
use Bands;
use Geomag;
use CmdAlias;
use Carp;

package main;

@inqueue = ();					# the main input queue, an array of hashes
$systime = 0;					# the time now (in seconds)
$version = 1.5;					# the version no of the software

# handle disconnections
sub disconnect
{
	my $dxchan = shift;
	return if !defined $dxchan;
	$dxchan->disconnect();
}

# handle incoming messages
sub rec
{
	my ($conn, $msg, $err) = @_;
	my $dxchan = DXChannel->get_by_cnum($conn); # get the dxconnnect object for this message
	
	if (defined $err && $err) {
		disconnect($dxchan) if defined $dxchan;
		return;
	}
	
	# set up the basic channel info - this needs a bit more thought - there is duplication here
	if (!defined $dxchan) {
		my ($sort, $call, $line) = $msg =~ /^(\w)(\S+)\|(.*)$/;
		
		# is there one already connected?
		if (DXChannel->get($call)) {
			my $mess = DXM::msg($lang, 'conother', $call);
			dbg('chan', "-> D $call $mess\n"); 
			$conn->send_now("D$call|$mess");
			sleep(1);
			dbg('chan', "-> Z $call bye\n");
			$conn->send_now("Z$call|bye"); # this will cause 'client' to disconnect
			return;
		}
		
		# is there one already connected elsewhere in the cluster?
		if (DXCluster->get($call)) {
			my $mess = DXM::msg($lang, 'concluster', $call);
			dbg('chan', "-> D $call $mess\n"); 
			$conn->send_now("D$call|$mess");
			sleep(1);
			dbg('chan', "-> Z $call bye\n");
			$conn->send_now("Z$call|bye"); # this will cause 'client' to disconnect
			return;
		}
		
		my $user = DXUser->get($call);
		if (!defined $user) {
			$user = DXUser->new($call);
		} else {
			$user->{lang} = $main::lang if !$user->{lang}; # to autoupdate old systems
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
	Log('cluster', "DXSpider V$version stopped");
	exit(0);
}

# the reaper of children
sub reap
{
	my $cpid = wait;
}

# this is where the input queue is dealt with and things are dispatched off to other parts of
# the cluster
sub process_inqueue
{
	my $self = shift @inqueue;
	return if !$self;
	
	my $data = $self->{data};
	my $dxchan = $self->{dxchan};
	my ($sort, $call, $line) = $data =~ /^(\w)(\w+)\|(.*)$/;
	
	# do the really sexy console interface bit! (Who is going to do the TK interface then?)
	dbg('chan', "<- $sort $call $line\n");
	
	# handle A records
	my $user = $dxchan->user;
	if ($sort eq 'A' || $sort eq 'O') {
		$dxchan->start($line, $sort);  
	} elsif ($sort eq 'D') {
		die "\$user not defined for $call" if !defined $user;
		
		# normal input
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

$systime = time;

# open the debug file, set various FHs to be unbuffered
foreach (@debug) {
	dbgadd($_);
}
STDOUT->autoflush(1);

Log('cluster', "DXSpider V$version started");

# banner
print "DXSpider DX Cluster Version $version\nCopyright (c) 1998 Dirk Koopman G1TLH\n";

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
$SIG{'CHLD'} = \&reap;

# read in system messages
DXM->init();

# read in command aliases
CmdAlias->init();

# initialise the protocol engine
DXProt->init();

# initialise the Geomagnetic data engine
Geomag->init();

# initial the Spot stuff
Spot->init();

# put in a DXCluster node for us here so we can add users and take them away
DXNode->new(0, $mycall, 0, 1, $DXProt::myprot_version); 

# read in any existing message headers and clean out old crap
print "reading existing message headers\n";
DXMsg->init();
DXMsg::clean_old();

# read in any cron jobs
print "reading cron jobs\n";
DXCron->init();

# this, such as it is, is the main loop!
print "orft we jolly well go ...\n";
for (;;) {
	my $timenow;
	Msg->event_loop(1, 0.001);
	$timenow = time;
	process_inqueue();			# read in lines from the input queue and despatch them
	
	# do timed stuff, ongoing processing happens one a second
	if ($timenow != $systime) {
		$systime = $timenow;
		$cldate = &cldate();
		$ztime = &ztime();
		DXCron::process();      # do cron jobs
		DXCommandmode::process(); # process ongoing command mode stuff
		DXProt::process();		# process ongoing ak1a pcxx stuff
		DXConnect::process();
	}
	if ($decease) {
		last if --$decease <= 0;
	}
}


