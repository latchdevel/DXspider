#!/usr/bin/env perl
#
# This is the DX cluster 'daemon'. It sits in the middle of its little
# web of client routines sucking and blowing data where it may.
#
# Hence the name of 'spider' (although it may become 'dxspider')
#
# Copyright (c) 1998 Dirk Koopman G1TLH
#
#
#

package main;

require 5.10.1;
use warnings;

use vars qw($root $is_win $systime $lockfn @inqueue $starttime $lockfn @outstanding_connects
			$zombies @listeners $lang $myalias @debug $userfn $clusteraddr
			$clusterport $mycall $decease $routeroot $me $reqreg $bumpexisting
			$allowdxby $dbh $dsn $dbuser $dbpass $do_xml $systime_days $systime_daystart
			$can_encode $maxconnect_user $maxconnect_node $idle_interval $log_flush_interval
			$broadcast_debug 
		   );

$lang = 'en';					# default language
$clusteraddr = '127.0.0.1';		# cluster tcp host address - used for things like console.pl
$clusterport = 27754;			# cluster tcp port
$yes = 'Yes';					# visual representation of yes
$no = 'No';						# ditto for no
$user_interval = 11*60;			# the interval between unsolicited prompts if no traffic

# make sure that modules are searched in the order local then perl
BEGIN {
	umask 002;

	# take into account any local::lib that might be present
	eval {
		require local::lib;
	};
	import local::lib unless ($@);

	# root of directory tree for this system
	$root = "/spider";
	$root = $ENV{'DXSPIDER_ROOT'} if $ENV{'DXSPIDER_ROOT'};

	unshift @INC, "$root/perl";	# this IS the right way round!
	unshift @INC, "$root/local";

	# do some validation of the input
	die "The directory $root doesn't exist, please RTFM" unless -d $root;
	die "$root/local doesn't exist, please RTFM" unless -d "$root/local";
	die "$root/local/DXVars.pm doesn't exist, please RTFM" unless -e "$root/local/DXVars.pm";

	# create some directories
	mkdir "$root/local_cmd", 02774 unless -d "$root/local_cmd";

	# locally stored data lives here
	my $local_data = "$root/local_data";
	mkdir $local_data, 02774 unless -d $local_data;

	# try to create and lock a lockfile (this isn't atomic but
	# should do for now
	$lockfn = "$root/local_data/cluster.lck";       # lock file name
	if (-w $lockfn) {
		open(CLLOCK, "$lockfn") or die "Can't open Lockfile ($lockfn) $!";
		my $pid = <CLLOCK>;
		if ($pid) {
			chomp $pid;
			if (kill 0, $pid) {
				warn "Lockfile ($lockfn) and process $pid exist, another cluster running?\n";
				exit 1;
			}
		}
		unlink $lockfn;
		close CLLOCK;
	}
	open(CLLOCK, ">$lockfn") or die "Can't open Lockfile ($lockfn) $!";
	print CLLOCK "$$\n";
	close CLLOCK;

	$is_win = ($^O =~ /^MS/ || $^O =~ /^OS-2/) ? 1 : 0; # is it Windows?
	$systime = time;
	
}

use DXVars;
use SysVar;

use strict;

use Mojo::IOLoop;

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
use DXXml;
use DXSql;
use IsoTime;
use BPQMsg;

use Data::Dumper;
use IO::File;
use Fcntl ':flock';
use POSIX ":sys_wait_h";
use Version;
use Web;

use Local;


@inqueue = ();					# the main input queue, an array of hashes
$systime = 0;					# the time now (in seconds)
$starttime = 0;                 # the starting time of the cluster
@outstanding_connects = ();     # list of outstanding connects
@listeners = ();				# list of listeners
$reqreg = 0;					# 1 = registration required, 2 = deregister people
$bumpexisting = 1;				# 1 = allow new connection to disconnect old, 0 - don't allow it
$allowdxby = 0;					# 1 = allow "dx by <othercall>", 0 - don't allow it
$maxconnect_user = 3;			# the maximum no of concurrent connections a user can have at a time
$maxconnect_node = 0;			# Ditto but for nodes. In either case if a new incoming connection
								# takes the no of references in the routing table above these numbers
								# then the connection is refused. This only affects INCOMING connections.
$idle_interval = 0.500;	        # the wait between invocations of the main idle loop processing.
$log_flush_interval = 2;		# interval to wait between log flushes

our $ending;					# signal that we are ending;
our $broadcast_debug;			# allow broadcasting of debug info down "enhanced" user connections
our $clssecs;					# the amount of cpu time the DXSpider process have consumed
our $cldsecs;					# the amount of cpu time any child processes have consumed


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

# handle incoming messages
sub new_channel
{
	my ($conn, $msg) = @_;
	my ($sort, $call, $line) = DXChannel::decode_input(0, $msg);
	return unless defined $sort;

	my ($dxchan, $user);
	
	if (is_webcall($call) && $conn->isa('IntMsg')) {
		my $newcall = find_next_webcall();
		unless ($newcall) {
			already_conn($conn, $call, "Maximum no of web connected connects ($Web::maxssid) exceeded");
			return;
		}
		$call = $newcall;
		$user = DXUser::get_current($call);
		unless ($user) {
			$user = DXUser->new($call);
			$user->sort('W');
			$user->wantbeep(0);
			$user->name('web');
			$user->qth('on the web');
			$user->homenode($main::mycall);
			$user->lat($main::mylatitude);
			$user->long($main::mylongitude);
			$user->qra($main::mylocator);
		}
		$conn->conns($call);
		$dxchan = Web->new($call, $conn, $user);
		$dxchan->enhanced(1);
		$dxchan->ve7cc(1);
		$msg =~ s/^A#WEB|/A$call|/;
		$conn->send_now("C$call");
	} else {
		# "Normal" connections
		unless (is_callsign($call)) {
			already_conn($conn, $call, DXM::msg($lang, "illcall", $call));
			return;
		}

		# set up the basic channel info for "Normal" Users
		# is there one already connected to me - locally?
	
		$user = DXUser::get_current($call);
		$dxchan = DXChannel::get($call);
		if ($dxchan) {
			if ($user && $user->is_node) {
				already_conn($conn, $call, DXM::msg($lang, 'conother', $call, $main::mycall));
				return;
			}
			if ($bumpexisting) {
				my $ip = $dxchan->hostname;
				$dxchan->send_now('D', DXM::msg($lang, 'conbump', $call, $ip));
				LogDbg('DXCommand', "$call bumped off by $ip, disconnected");
				$dxchan->disconnect;
			} else {
				already_conn($conn, $call, DXM::msg($lang, 'conother', $call, $main::mycall));
				return;
			}
		}
		
		# (fairly) politely disconnect people that are connected to too many other places at once
		my $r = Route::get($call);
		if ($conn->{sort} && $conn->{sort} =~ /^I/ && $r && $user) {
			my @n = $r->parents;
			my $m = $r->isa('Route::Node') ? $maxconnect_node : $maxconnect_user;
			my $c = $user->maxconnect;
			my $v;
			$v = defined $c ? $c : $m;
			if ($v && @n >= $v) {
				my $nodes = join ',', @n;
				LogDbg('DXCommand', "$call has too many connections ($v) at $nodes - disconnected");
				already_conn($conn, $call, DXM::msg($lang, 'contomany', $call, $v, $nodes));
				return;
			}
		}
		
		# is he locked out ?
		my $basecall = $call;
		$basecall =~ s/-\d+$//;
		my $baseuser = DXUser::get_current($basecall);
		my $lock = $user->lockout if $user;
		if ($baseuser && $baseuser->lockout || $lock) {
			if (!$user || !defined $lock || $lock) {
				my $host = $conn->peerhost;
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
		} else {
			die "Invalid sort of user on $call = $sort";
		}
		
		# check that the conn has a callsign
		$conn->conns($call) if $conn->isa('IntMsg');
	}
	

	# set callbacks
	$conn->set_error(sub {my $err = shift; LogDbg('DXCommand', "Comms error '$err' received for call $dxchan->{call}"); $dxchan->disconnect(1);});
	$conn->set_on_eof(sub {$dxchan->disconnect});
	$conn->set_rproc(sub {my ($conn,$msg) = @_; $dxchan->rec($msg);});
	if ($sort eq 'W') {
		$dxchan->enhanced(1);
		$dxchan->sort('W');
	}
	$dxchan->rec($msg);
}


sub login
{
	return \&new_channel;
}

our $ceasing;

# cease running this program, close down all the connections nicely
sub cease
{
	my $dxchan;

	cluck("ceasing") if $ceasing; 
	
	return if $ceasing++;
	
	unless ($is_win) {
		$SIG{'TERM'} = 'IGNORE';
		$SIG{'INT'} = 'IGNORE';
	}

	DXUser::sync;

	if (defined &Local::finish) {
		eval {
			Local::finish();   # end local processing
		};
		dbg("Local::finish error $@") if $@;
	}


	# disconnect AGW
	AGWMsg::finish();
	BPQMsg::finish();

	# disconnect UDP customers
	UDPMsg::finish();

	# end everything else
	DXUser::finish();
	DXDupe::finish();

	# close all databases
	DXDb::closeall;

	# close all listeners
	foreach my $l (@listeners) {
		$l->close_server;
	}

	LogDbg('cluster', "DXSpider V$version, build $build (git: $gitversion) ended");
	dbg("bye bye everyone - bye bye");
	dbgclose();
	Logclose();

	$dbh->finish if $dbh;

	unlink $lockfn;
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


sub setup_start
{

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
	dbginit($broadcast_debug ? \&DXCommandmode::broadcast_debug : undef);
	foreach (@debug) {
		dbgadd($_);
	}
	STDOUT->autoflush(1);

	
	# try to load the database
	if (DXSql::init($dsn)) {
		$dbh = DXSql->new($dsn);
		$dbh = $dbh->connect($dsn, $dbuser, $dbpass) if $dbh;
	}

	# try to load Encode and Git
	{
		local $^W = 0;
		my $w = $SIG{__DIE__};
		$SIG{__DIE__} = 'IGNORE';
		eval { require Encode; };
		unless ($@) {
			import Encode;
			$can_encode = 1;
		}
		eval { require Git; };
		unless ($@) {
			import Git;
		
			# determine the real version number
			my $repo = Git->repository(Directory => "$root/.git");
			if ($repo) {
				my $desc = $repo->command_oneline(['describe', '--long'], STDERR => 0);
				if ($desc) {
					my ($v, $s, $b, $g) = $desc =~ /^([\d.]+)(?:\.(\d+))?-(\d+)-g([0-9a-f]+)/;
					$version = $v;
					$build = $b || 0;
					$gitversion = "$g\[r]";
				}
			}
		}
		$SIG{__DIE__} = $w;
	}

	# try to load XML::Simple
	DXXml::init();

	# banner
	my ($year) = (gmtime)[5];
	$year += 1900;
	LogDbg('cluster', "DXSpider V$version, build $build (git: $gitversion) started");
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
	DXUser::init(1);

	# look for the sysop and the alias user and complain if they aren't there
	{
		die "\$myalias \& \$mycall are the same ($mycall)!, they must be different (hint: make \$mycall = '${mycall}-2';). Oh and don't forget to rerun create_sysop.pl!" if $mycall eq $myalias;
		my $ref = DXUser::get($mycall);
		die "$mycall missing, run the create_sysop.pl script and please RTFM" unless $ref && $ref->priv == 9;
		my $oldsort = $ref->sort;
		if ($oldsort ne 'S') {
			$ref->sort('S');
			dbg "Resetting node type from $oldsort -> DXSpider ('S')";
		}
		$ref = DXUser::get($myalias);
		die "$myalias missing, run the create_sysop.pl script and please RTFM" unless $ref && $ref->priv == 9;
		$oldsort = $ref->sort;
		if ($oldsort ne 'U') {
			$ref->sort('U');
			dbg "Resetting sysop user type from $oldsort -> User ('U')";
		}
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

	dbg("BPQ Listener") if $BPQMsg::enable;
	BPQMsg::init(\&new_channel);

	dbg("UDP Listener") if $UDPMsg::enable;
	UDPMsg::init(\&new_channel);

	# load bad words
	dbg("load badwords: " . (BadWords::load or "Ok"));

	# prime some signals
	unless ($DB::VERSION) {
		$SIG{INT} = $SIG{TERM} = sub { $ending = 10; };
	}

	unless ($is_win) {
		$SIG{HUP} = 'IGNORE';
		$SIG{CHLD} = sub { $zombies++ };

		$SIG{PIPE} = sub { 	dbg("Broken PIPE signal received"); };
		$SIG{IO} = sub { 	dbg("SIGIO received"); };
		$SIG{WINCH} = $SIG{STOP} = $SIG{CONT} = 'IGNORE';
		$SIG{KILL} = 'DEFAULT';	# as if it matters....

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

	# read in database desriptors
	dbg("reading database descriptors ...");
	DXDb::load();

	# starting local stuff
	dbg("doing local initialisation ...");
	QSL::init(1);
	if (defined &Local::init) {
		eval {
			Local::init();
		};
		dbg("Local::init error $@") if $@;
	}


	# this, such as it is, is the main loop!
	dbg("orft we jolly well go ...");
	my $script = new Script "startup";
	$script->run($main::me) if $script;

	#open(DB::OUT, "|tee /tmp/aa");
}

our $io_disconnected;

sub idle_loop
{
	BPQMsg::process();

	if (defined &Local::process) {
		eval {
			Local::process();	# do any localised processing
		};
		dbg("Local::process error $@") if $@;
	}

	while ($ending) {
		my $dxchan;

		dbg("DXSpider Ending $ending");

		unless ($io_disconnected++) {

			# disconnect users
			foreach $dxchan (DXChannel::get_all_users) {
				$dxchan->disconnect;
			}

			# disconnect nodes
			foreach $dxchan (DXChannel::get_all_nodes) {
				next if $dxchan == $main::me;
				$dxchan->disconnect(2);
			}
			$main::me->disconnect;
		}

		Mojo::IOLoop->stop if --$ending <= 0;
	}
}

sub per_sec
{
	my $timenow = time;

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
	DXCron::process();			# do cron jobs
	IsoTime::update($systime);
	DXProt::process();			# process ongoing ak1a pcxx stuff
	DXConnect::process();
	DXUser::process();
	AGWMsg::process();
	
	Timer::handler();
	DXLog::flushall();
}

sub per_10_sec
{

}


sub per_minute
{

}

sub per_10_minute
{

}

sub per_hour
{

}

sub per_day
{

}

sub start_node
{
	dbg("Before Web::start_node");

	Mojo::IOLoop->start unless Mojo::IOLoop->is_running;

	dbg("After Web::start_node");
}

setup_start();

my $main_loop = Mojo::IOLoop->recurring($idle_interval => \&idle_loop);
my $log_flush_loop = Mojo::IOLoop->recurring($log_flush_interval => \&DXLog::flushall);
my $cpusecs_loop = Mojo::IOLoop->recurring(5 => sub {my @t = times; $clssecs = $t[0]+$t[1]; $cldsecs = $t[2]+$t[3]});
my $persec =  Mojo::IOLoop->recurring(1 => \&per_sec);
my $per10sec =  Mojo::IOLoop->recurring(10 => \&per_10_sec);
my $permin =  Mojo::IOLoop->recurring(60 => \&per_minute);
my $per10min =  Mojo::IOLoop->recurring(600 => \&per_10_minute);
my $perhour =  Mojo::IOLoop->recurring(3600 => \&per_hour);
my $perday =  Mojo::IOLoop->recurring(86400 => \&per_day);

start_node();

cease(0);

exit(0);

