#!/usr/bin/perl -w
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

require 5.004;

# make sure that modules are searched in the order local then perl
BEGIN {
	umask 002;
	
	# root of directory tree for this system
	$root = "/spider"; 
	$root = $ENV{'DXSPIDER_ROOT'} if $ENV{'DXSPIDER_ROOT'};
	
	unshift @INC, "$root/perl";	# this IS the right way round!
	unshift @INC, "$root/local";

	# try to create and lock a lockfile (this isn't atomic but 
	# should do for now
	$lockfn = "$root/perl/cluster.lck";       # lock file name
	if (-e $lockfn) {
		open(CLLOCK, "$lockfn") or die "Can't open Lockfile ($lockfn) $!";
		my $pid = <CLLOCK>;
		chomp $pid;
		die "Lockfile ($lockfn) and process $pid exist, another cluster running?" if kill 0, $pid;
		close CLLOCK;
	}
	open(CLLOCK, ">$lockfn") or die "Can't open Lockfile ($lockfn) $!";
	print CLLOCK "$$\n";
	close CLLOCK;

	$is_win = ($^O =~ /^MS/ || $^O =~ /^OS-2/) ? 1 : 0; # is it Windows?
	$systime = time;
}

use DXVars;
use Msg;
use IntMsg;
use Internet;
use Listeners;
use ExtMsg;
use AGWConnect;
use AGWMsg;
use DXDebug;
use DXLog;
use DXLogPrint;
use DXUtil;
use DXChannel;
use DXUser;
use DXM;
use DXCommandmode;
use DXProtVars;
use DXProtout;
use DXProt;
use DXMsg;
use DXCluster;
use DXCron;
use DXConnect;
use DXBearing;
use DXDb;
use DXHash;
use DXDupe;
use Prefix;
use Spot;
use Bands;
use Keps;
use Minimuf;
use Sun;
use Geomag;
use CmdAlias;
use Filter;
use AnnTalk;
use BBS;
use WCY;
use BadWords;
use Timer;

use Data::Dumper;
use IO::File;
use Fcntl ':flock'; 
use POSIX ":sys_wait_h";

use Local;

package main;

use strict;
use vars qw(@inqueue $systime $version $starttime $lockfn @outstanding_connects 
			$zombies $root @listeners $lang $myalias @debug $userfn $clusteraddr 
			$clusterport $mycall $decease $build $is_win
		   );

@inqueue = ();					# the main input queue, an array of hashes
$systime = 0;					# the time now (in seconds)
$version = "1.48";				# the version no of the software
$starttime = 0;                 # the starting time of the cluster   
#@outstanding_connects = ();     # list of outstanding connects
@listeners = ();				# list of listeners

      
# send a message to call on conn and disconnect
sub already_conn
{
	my ($conn, $call, $mess) = @_;

	$conn->disable_read(1);
	dbg('chan', "-> D $call $mess\n"); 
	$conn->send_now("D$call|$mess");
	sleep(2);
	$conn->disconnect;
}

sub error_handler
{
	my $dxchan = shift;
	$dxchan->{conn}->set_error(undef) if exists $dxchan->{conn};
	$dxchan->disconnect(1);
}

# handle incoming messages
sub new_channel
{
	my ($conn, $msg) = @_;
	my ($sort, $call, $line) = DXChannel::decode_input(0, $msg);
	return unless defined $sort;
	
	# set up the basic channel info
	# is there one already connected to me - locally? 
	my $user = DXUser->get($call);
	my $dxchan = DXChannel->get($call);
	if ($dxchan) {
		my $mess = DXM::msg($lang, ($user && $user->is_node) ? 'concluster' : 'conother', $call, $main::mycall);
		already_conn($conn, $call, $mess);
		return;
	}
	
	# is there one already connected elsewhere in the cluster?
	if ($user) {
		if (($user->is_node || $call eq $myalias) && !DXCluster->get_exact($call)) {
			;
		} else {
			if (my $ref = DXCluster->get_exact($call)) {
				my $mess = DXM::msg($lang, 'concluster', $call, $ref->mynode->dxchancall);
				already_conn($conn, $call, $mess);
				return;
			}
		}
		$user->{lang} = $main::lang if !$user->{lang}; # to autoupdate old systems
	} else {
		if (my $ref = DXCluster->get_exact($call)) {
			my $mess = DXM::msg($lang, 'concluster', $call, $ref->mynode->dxchancall);
			already_conn($conn, $call, $mess);
			return;
		}
		$user = DXUser->new($call);
	}
	
	# is he locked out ?
	if ($user->lockout) {
		Log('DXCommand', "$call is locked out, disconnected");
		$conn->disconnect;
		return;
	}

	# create the channel
	$dxchan = DXCommandmode->new($call, $conn, $user) if $user->is_user;
	$dxchan = DXProt->new($call, $conn, $user) if $user->is_node;
	$dxchan = BBS->new($call, $conn, $user) if $user->is_bbs;
	die "Invalid sort of user on $call = $sort" if !$dxchan;

	# check that the conn has a callsign
	$conn->conns($call) if $conn->isa('IntMsg');

	# set callbacks
	$conn->set_error(sub {error_handler($dxchan)});
	$conn->set_rproc(sub {my ($conn,$msg) = @_; rec($dxchan, $conn, $msg);});
	rec($dxchan, $conn, $msg);
}

sub rec	
{
	my ($dxchan, $conn, $msg) = @_;
	
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
	return \&new_channel;
}

# cease running this program, close down all the connections nicely
sub cease
{
	my $dxchan;

	unless ($is_win) {
		$SIG{'TERM'} = 'IGNORE';
		$SIG{'INT'} = 'IGNORE';
	}
	
	DXUser::sync;

	eval {
		Local::finish();   # end local processing
	};
	dbg('local', "Local::finish error $@") if $@;

	# disconnect nodes
	foreach $dxchan (DXChannel->get_all_nodes) {
	    $dxchan->disconnect(2) unless $dxchan == $DXProt::me;
	}
	Msg->event_loop(100, 0.01);

	# disconnect users
	foreach $dxchan (DXChannel->get_all_users) {
		$dxchan->disconnect;
	}

	# disconnect AGW
	AGWMsg::finish();

	# end everything else
	Msg->event_loop(100, 0.01);
	DXUser::finish();
	DXDupe::finish();

	# close all databases
	DXDb::closeall;

	# close all listeners
	foreach my $l (@listeners) {
		$l->close_server;
	}

	dbg('chan', "DXSpider version $version, build $build ended");
	Log('cluster', "DXSpider V$version, build $build ended");
	dbgclose();
	Logclose();
	unlink $lockfn;
#	$SIG{__WARN__} = $SIG{__DIE__} =  sub {my $a = shift; cluck($a); };
	exit(0);
}

# the reaper of children
sub reap
{
	my $cpid;
	while (($cpid = waitpid(-1, WNOHANG)) > 0) {
		dbg('reap', "cpid: $cpid");
#		Msg->pid_gone($cpid);
		$zombies-- if $zombies > 0;
	}
	dbg('reap', "cpid: $cpid");
}

# this is where the input queue is dealt with and things are dispatched off to other parts of
# the cluster
sub process_inqueue
{
	my $self = shift @inqueue;
	return if !$self;
	
	my $data = $self->{data};
	my $dxchan = $self->{dxchan};
	my $error;
	my ($sort, $call, $line) = DXChannel::decode_input($dxchan, $data);
	return unless defined $sort;
	
	# do the really sexy console interface bit! (Who is going to do the TK interface then?)
	dbg('chan', "<- $sort $call $line\n") unless $sort eq 'D';

	# handle A records
	my $user = $dxchan->user;
	if ($sort eq 'A' || $sort eq 'O') {
		$dxchan->start($line, $sort);  
	} elsif ($sort eq 'I') {
		die "\$user not defined for $call" if !defined $user;
		# normal input
		$dxchan->normal($line);
		$dxchan->disconnect if ($dxchan->{state} eq 'bye');
	} elsif ($sort eq 'Z') {
		$dxchan->disconnect;
	} elsif ($sort eq 'D') {
		;                       # ignored (an echo)
	} else {
		print STDERR atime, " Unknown command letter ($sort) received from $call\n";
	}
}

sub uptime
{
	my $t = $systime - $starttime;
	my $days = int $t / 86400;
	$t -= $days * 86400;
	my $hours = int $t / 3600;
	$t -= $hours * 3600;
	my $mins = int $t / 60;
	return sprintf "%d %02d:%02d", $days, $hours, $mins;
}

sub AGWrestart
{
	AGWMsg::init(\&new_channel);
}

#############################################################
#
# The start of the main line of code 
#
#############################################################

$starttime = $systime = time;
$lang = 'en' unless $lang;

# open the debug file, set various FHs to be unbuffered
dbginit();
foreach (@debug) {
	dbgadd($_);
}
STDOUT->autoflush(1);

# calculate build number
$build = $main::version;

my @fn;
open(CL, "$main::root/perl/cluster.pl") or die "Cannot open cluster.pl $!";
while (<CL>) {
	next unless /^use\s+([\w:_]+)/;
	push @fn, $1;
}
close CL;
foreach my $fn (@fn) {
	open(CL, "$main::root/perl/${fn}.pm") or next;
	while (<CL>) {
		if (/^#\s+\$Id:\s+[\w\._]+,v\s+(\d+\.\d+)/ ) {
			$build += $1;
			last;
		}
	}
	close CL;
}

Log('cluster', "DXSpider V$version, build $build started");

# banner
dbg('err', "DXSpider Version $version, build $build started", "Copyright (c) 1998-2001 Dirk Koopman G1TLH");

# load Prefixes
dbg('err', "loading prefixes ...");
Prefix::load();

# load band data
dbg('err', "loading band data ...");
Bands::load();

# initialise User file system
dbg('err', "loading user file system ..."); 
DXUser->init($userfn, 1);

# start listening for incoming messages/connects
dbg('err', "starting listeners ...");
my $conn = IntMsg->new_server($clusteraddr, $clusterport, \&login);
$conn->conns("Server $clusteraddr/$clusterport");
push @listeners, $conn;
dbg('err', "Internal port: $clusteraddr $clusterport");
foreach my $l (@main::listen) {
	$conn = ExtMsg->new_server($l->[0], $l->[1], \&login);
	$conn->conns("Server $l->[0]/$l->[1]");
	push @listeners, $conn;
	dbg('err', "External Port: $l->[0] $l->[1]");
}
AGWrestart();

# load bad words
dbg('err', "load badwords: " . (BadWords::load or "Ok"));

# prime some signals
unless ($DB::VERSION) {
	$SIG{INT} = $SIG{TERM} = sub { $decease = 1 };
}

unless ($is_win) {
	$SIG{HUP} = 'IGNORE';
	$SIG{CHLD} = sub { $zombies++ };
	
	$SIG{PIPE} = sub { 	dbg('err', "Broken PIPE signal received"); };
	$SIG{IO} = sub { 	dbg('err', "SIGIO received"); };
	$SIG{WINCH} = $SIG{STOP} = $SIG{CONT} = 'IGNORE';
	$SIG{KILL} = 'DEFAULT';     # as if it matters....

	# catch the rest with a hopeful message
	for (keys %SIG) {
		if (!$SIG{$_}) {
			#		dbg('chan', "Catching SIG $_");
			$SIG{$_} = sub { my $sig = shift;	DXDebug::confess("Caught signal $sig");  }; 
		}
	}
}

# start dupe system
DXDupe::init();

# read in system messages
DXM->init();

# read in command aliases
CmdAlias->init();

# initialise the Geomagnetic data engine
Geomag->init();
WCY->init();

# initial the Spot stuff
Spot->init();

# initialise the protocol engine
dbg('err', "reading in duplicate spot and WWV info ...");
DXProt->init();

# put in a DXCluster node for us here so we can add users and take them away
DXNode->new($DXProt::me, $mycall, 0, 1, $DXProt::myprot_version); 

# read in any existing message headers and clean out old crap
dbg('err', "reading existing message headers ...");
DXMsg->init();
DXMsg::clean_old();

# read in any cron jobs
dbg('err', "reading cron jobs ...");
DXCron->init();

# read in database descriptors
dbg('err', "reading database descriptors ...");
DXDb::load();

# starting local stuff
dbg('err', "doing local initialisation ...");
eval {
	Local::init();
};
dbg('local', "Local::init error $@") if $@;

# print various flags
#dbg('err', "seful info - \$^D: $^D \$^W: $^W \$^S: $^S \$^P: $^P");

# this, such as it is, is the main loop!
dbg('err', "orft we jolly well go ...");

#open(DB::OUT, "|tee /tmp/aa");

for (;;) {
#	$DB::trace = 1;
	
	Msg->event_loop(10, 0.010);
	my $timenow = time;
	process_inqueue();			# read in lines from the input queue and despatch them
#	$DB::trace = 0;
	
	# do timed stuff, ongoing processing happens one a second
	if ($timenow != $systime) {
		reap if $zombies;
		$systime = $timenow;
		DXCron::process();      # do cron jobs
		DXCommandmode::process(); # process ongoing command mode stuff
		DXProt::process();		# process ongoing ak1a pcxx stuff
		DXConnect::process();
		DXMsg::process();
		DXDb::process();
		DXUser::process();
		DXDupe::process();
		AGWMsg::process();
				
		eval { 
			Local::process();       # do any localised processing
		};
		dbg('local', "Local::process error $@") if $@;
	}
	if ($decease) {
		last if --$decease <= 0;
	}
}
cease(0);
exit(0);


