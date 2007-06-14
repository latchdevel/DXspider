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

	# do some validation of the input
	die "The directory $root doesn't exist, please RTFM" unless -d $root;
	die "$root/local doesn't exist, please RTFM" unless -d "$root/local";
	die "$root/local/DXVars.pm doesn't exist, please RTFM" unless -e "$root/local/DXVars.pm";
	
	mkdir "$root/local_cmd", 0777 unless -d "$root/local_cmd";
	

	# try to create and lock a lockfile (this isn't atomic but 
	# should do for now
	$lockfn = "$root/local/cluster.lck";       # lock file name
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
use DXCron;
use DXConnect;
use DXBearing;
use DXDb;
use DXHash;
use DXDupe;
use Script;
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
use Route;
use Route::Node;
use Route::User;
use Editable;
use Mrtg;
use USDB;
use UDPMsg;
use QSL;
use RouteDB;
use DXXml;
use DXSql;
use IsoTime;

use Data::Dumper;
use IO::File;
use Fcntl ':flock'; 
use POSIX ":sys_wait_h";
use Version;

use Local;

package main;

use strict;
use vars qw(@inqueue $systime $starttime $lockfn @outstanding_connects 
			$zombies $root @listeners $lang $myalias @debug $userfn $clusteraddr 
			$clusterport $mycall $decease $is_win $routeroot $me $reqreg $bumpexisting
			$allowdxby $dbh $dsn $dbuser $dbpass $do_xml $systime_days $systime_daystart
		   );

@inqueue = ();					# the main input queue, an array of hashes
$systime = 0;					# the time now (in seconds)
$starttime = 0;                 # the starting time of the cluster   
@outstanding_connects = ();     # list of outstanding connects
@listeners = ();				# list of listeners
$reqreg = 0;					# 1 = registration required, 2 = deregister people
$bumpexisting = 1;				# 1 = allow new connection to disconnect old, 0 - don't allow it
$allowdxby = 0;					# 1 = allow "dx by <othercall>", 0 - don't allow it


# send a message to call on conn and disconnect
sub already_conn
{
	my ($conn, $call, $mess) = @_;

	$conn->disable_read(1);
	dbg("-> D $call $mess\n") if isdbg('chan'); 
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

	unless (is_callsign($call)) {
		already_conn($conn, $call, DXM::msg($lang, "illcall", $call));
		return;
	}

	# set up the basic channel info
	# is there one already connected to me - locally? 
	my $user = DXUser->get_current($call);
	my $dxchan = DXChannel::get($call);
	if ($dxchan) {
		if ($user && $user->is_node) {
			already_conn($conn, $call, DXM::msg($lang, 'concluster', $call, $main::mycall));
			return;
		}
		if ($bumpexisting) {
			my $ip = $conn->{peerhost} || 'unknown';
			$dxchan->send_now('D', DXM::msg($lang, 'conbump', $call, $ip));
			LogDbg('DXCommand', "$call bumped off by $ip, disconnected");
			$dxchan->disconnect;
		} else {
			already_conn($conn, $call, DXM::msg($lang, 'conother', $call, $main::mycall));
			return;
		}
	}

	# is he locked out ?
	my $basecall = $call;
	$basecall =~ s/-\d+$//;
	my $baseuser = DXUser->get_current($basecall);
	my $lock = $user->lockout if $user;
	if ($baseuser && $baseuser->lockout || $lock) {
		if (!$user || !defined $lock || $lock) {
			my $host = $conn->{peerhost} || "unknown";
			LogDbg('DXCommand', "$call on $host is locked out, disconnected");
			$conn->disconnect;
			return;
		}
	}
	
	if ($user) {
		$user->{lang} = $main::lang if !$user->{lang}; # to autoupdate old systems
	} else {
		$user = DXUser->new($call);
	}
	
	# create the channel
	if ($user->is_node) {
		$dxchan = DXProt->new($call, $conn, $user);
	} elsif ($user->is_user) {
		$dxchan = DXCommandmode->new($call, $conn, $user);
	} elsif ($user->is_bbs) {
		$dxchan = BBS->new($call, $conn, $user);
	} else {
		die "Invalid sort of user on $call = $sort";
	}

	# check that the conn has a callsign
	$conn->conns($call) if $conn->isa('IntMsg');

	# set callbacks
	$conn->set_error(sub {error_handler($dxchan)});
	$conn->set_rproc(sub {my ($conn,$msg) = @_; $dxchan->rec($msg);});
	$dxchan->rec($msg);
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
	dbg("Local::finish error $@") if $@;

	# disconnect nodes
	foreach $dxchan (DXChannel::get_all_nodes) {
	    $dxchan->disconnect(2) unless $dxchan == $main::me;
	}
	Msg->event_loop(100, 0.01);

	# disconnect users
	foreach $dxchan (DXChannel::get_all_users) {
		$dxchan->disconnect;
	}

	# disconnect AGW
	AGWMsg::finish();

	# disconnect UDP customers
	UDPMsg::finish();

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

	LogDbg('cluster', "DXSpider V$version, build $build ended");
	dbgclose();
	Logclose();

	$dbh->finish if $dbh;
	
	unlink $lockfn;
#	$SIG{__WARN__} = $SIG{__DIE__} =  sub {my $a = shift; cluck($a); };
	exit(0);
}

# the reaper of children
sub reap
{
	my $cpid;
	while (($cpid = waitpid(-1, WNOHANG)) > 0) {
		dbg("cpid: $cpid") if isdbg('reap');
#		Msg->pid_gone($cpid);
		$zombies-- if $zombies > 0;
	}
	dbg("cpid: $cpid") if isdbg('reap');
}

# this is where the input queue is dealt with and things are dispatched off to other parts of
# the cluster

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
$systime_days = int ($systime / 86400);
$systime_daystart = $systime_days * 86400; 
$lang = 'en' unless $lang;

unless ($DB::VERSION) {
	$SIG{INT} = $SIG{TERM} = \&cease;
}

# open the debug file, set various FHs to be unbuffered
dbginit(\&DXCommandmode::broadcast_debug);
foreach (@debug) {
	dbgadd($_);
}
STDOUT->autoflush(1);

# try to load the database
if (DXSql::init($dsn)) {
	$dbh = DXSql->new($dsn);
	$dbh = $dbh->connect($dsn, $dbuser, $dbpass) if $dbh;
}

# try to load XML::Simple
DXXml::init();

# banner
my ($year) = (gmtime)[5];
$year += 1900;
LogDbg('cluster', "DXSpider V$version, build $build started");
dbg("Copyright (c) 1998-$year Dirk Koopman G1TLH");

# load Prefixes
dbg("loading prefixes ...");
dbg(USDB::init());
my $r = Prefix::init();
confess $r if $r;

# load band data
dbg("loading band data ...");
Bands::load();

# initialise User file system
dbg("loading user file system ..."); 
DXUser->init($userfn, 1);

# look for the sysop and the alias user and complain if they aren't there
{
	my $ref = DXUser->get($mycall);
	die "$mycall missing, run the create_sysop.pl script and please RTFM" unless $ref && $ref->priv == 9;
	$ref = DXUser->get($myalias);
	die "$myalias missing, run the create_sysop.pl script and please RTFM" unless $ref && $ref->priv == 9;
}

# start listening for incoming messages/connects
dbg("starting listeners ...");
my $conn = IntMsg->new_server($clusteraddr, $clusterport, \&login);
$conn->conns("Server $clusteraddr/$clusterport using IntMsg");
push @listeners, $conn;
dbg("Internal port: $clusteraddr $clusterport using IntMsg");
foreach my $l (@main::listen) {
	no strict 'refs';
	my $pkg = $l->[2] || 'ExtMsg';
	my $login = $l->[3] || 'login'; 
	
	$conn = $pkg->new_server($l->[0], $l->[1], \&{"${pkg}::${login}"});
	$conn->conns("Server $l->[0]/$l->[1] using ${pkg}::${login}");
	push @listeners, $conn;
	dbg("External Port: $l->[0] $l->[1] using ${pkg}::${login}");
}

dbg("AGW Listener") if $AGWMsg::enable;
AGWrestart();

dbg("UDP Listener") if $UDPMsg::enable;
UDPMsg::init(\&new_channel);

# load bad words
dbg("load badwords: " . (BadWords::load or "Ok"));

# prime some signals
unless ($DB::VERSION) {
	$SIG{INT} = $SIG{TERM} = sub { $decease = 1 };
}

unless ($is_win) {
	$SIG{HUP} = 'IGNORE';
	$SIG{CHLD} = sub { $zombies++ };
	
	$SIG{PIPE} = sub { 	dbg("Broken PIPE signal received"); };
	$SIG{IO} = sub { 	dbg("SIGIO received"); };
	$SIG{WINCH} = $SIG{STOP} = $SIG{CONT} = 'IGNORE';
	$SIG{KILL} = 'DEFAULT';     # as if it matters....

	# catch the rest with a hopeful message
	for (keys %SIG) {
		if (!$SIG{$_}) {
			#		dbg("Catching SIG $_") if isdbg('chan');
			$SIG{$_} = sub { my $sig = shift;	DXDebug::confess("Caught signal $sig");  }; 
		}
	}
}

# start dupe system
dbg("Starting Dupe system");
DXDupe::init();

# read in system messages
dbg("Read in Messages");
DXM->init();

# read in command aliases
dbg("Read in Aliases");
CmdAlias->init();

# initialise the Geomagnetic data engine
dbg("Start WWV");
Geomag->init();
dbg("Start WCY");
WCY->init();

# initial the Spot stuff
dbg("Starting DX Spot system");
Spot->init();

# initialise the protocol engine
dbg("Start Protocol Engines ...");
DXProt->init();

# put in a DXCluster node for us here so we can add users and take them away
$routeroot = Route::Node->new($mycall, $version*100+5300, Route::here($main::me->here)|Route::conf($main::me->conf));
$routeroot->do_pc9x(1);
$routeroot->via_pc92(1);

# make sure that there is a routing OUTPUT node default file
#unless (Filter::read_in('route', 'node_default', 0)) {
#	my $dxcc = $main::me->dxcc;
#	$Route::filterdef->cmd($main::me, 'route', 'accept', "node_default call $mycall" );
#}

# read in any existing message headers and clean out old crap
dbg("reading existing message headers ...");
DXMsg->init();
DXMsg::clean_old();

# read in any cron jobs
dbg("reading cron jobs ...");
DXCron->init();

# read in database descriptors
dbg("reading database descriptors ...");
DXDb::load();

# starting local stuff
dbg("doing local initialisation ...");
QSL::init(1);
eval {
	Local::init();
};
dbg("Local::init error $@") if $@;

# this, such as it is, is the main loop!
dbg("orft we jolly well go ...");
my $script = new Script "startup";
$script->run($main::me) if $script;

#open(DB::OUT, "|tee /tmp/aa");

for (;;) {
#	$DB::trace = 1;
	
	Msg->event_loop(10, 0.010);
	my $timenow = time;

	DXChannel::process();
	
#	$DB::trace = 0;
	
	# do timed stuff, ongoing processing happens one a second
	if ($timenow != $systime) {
		reap() if $zombies;
		$systime = $timenow;
		my $days = int ($systime / 86400);
		if ($systime_days != $days) {
			$systime_days = $days;
			$systime_daystart = $days * 86400;
		}
		IsoTime::update($systime);
		DXCron::process();      # do cron jobs
		DXCommandmode::process(); # process ongoing command mode stuff
		DXXml::process();
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
		dbg("Local::process error $@") if $@;
	}
	if ($decease) {
		last if --$decease <= 0;
	}
}
cease(0);
exit(0);


