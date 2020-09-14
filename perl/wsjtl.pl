#!/usr/bin/env perl
#
# A basic listener and decoder of wsjtx packets
#
#

our ($systime, $root, $local_data);

BEGIN {
	umask 002;
	$SIG{'__WARN__'} = sub { warn $_[0] if $DOWARN };
			
	# take into account any local::lib that might be present
	eval {
		require local::lib;
	};
	unless ($@) {
#		import local::lib;
		import local::lib qw(/spider/perl5lib);
	} 

	# root of directory tree for this system
	$root = "/spider";
	$root = $ENV{'DXSPIDER_ROOT'} if $ENV{'DXSPIDER_ROOT'};

	unshift @INC, "$root/perl5lib" unless grep {$_ eq "$root/perl5lib"} @INC;
	unshift @INC, "$root/perl";	# this IS the right way round!
	unshift @INC, "$root/local";

	# do some validation of the input
	die "The directory $root doesn't exist, please RTFM" unless -d $root;

	# locally stored data lives here
	$local_data = "$root/local_data";
	mkdir $local_data, 02774 unless -d $local_data;

	# try to create and lock a lockfile (this isn't atomic but
	# should do for now
	$lockfn = "$root/local_data/wsjtxl.lck";       # lock file name
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

use strict;
use warnings;
use 5.22.0;

use Mojolicious 8.1;
use Mojo::IOLoop;
use Mojo::IOLoop::Server;
use DXDebug;
use DXUDP;

use WSJTX;

our $udp_host = '::';
our $udp_port = 2237;
our $tcp_host = '::';
our $tcp_port = 2238;

my $uh;							# the mojo handle for the UDP listener
my $th;							#  ditto TCP
my $wsjtx;						# the wsjtx decoder
my $cease;

our %slot;			  # where the connected TCP client structures live


dbginit('wsjtl');

my @queue;

$uh = DXUDP->new;
$uh->start(host => $udp_host, port => $udp_port) or die "Cannot listen on $udp_host:$udp_port $!\n";

$wsjtx = WSJTX->new();
$uh->on(read => \&_udpread);

$th = Mojo::IOLoop::Server->new;
$th->on(accept => \&_accept);
$th->listen(address => $tcp_host, port => $tcp_port);
$th->start;

Mojo::IOLoop->start() unless Mojo::IOLoop->is_running;

exit;

sub _udpread
{
	my ($handle, $data) = @_;

	my $host = $handle->peerhost;
	my $port = $handle->peerport;
   
	my $in = $wsjtx->handle($handle, $data, "$host:$port");

	distribute($in);
}

sub _accept
{
	my ($id, $handle) = @_;
	my $host = $handle->peerhost;
	my $port = $handle->peerport;

	
	my $s = $slot{"$host:$port"} = { addr => "$host:$port"};
	my $stream = $s->{stream} = Mojo::IOLoop::Stream->new($handle);
	$stream->on(error => sub { $stream->close; delete $s->{addr}});
	$stream->on(close => sub { delete $s->{addr}});
	$stream->on(read => sub {_tcpread($s, $_[1])});
	$stream->timeout(0);
	$stream->start;
}

sub _tcpread
{
	my $s = shift;
	my $data = shift;
	
	dbg("incoming: $data");
}

sub distribute
{
	my $in = shift;
	foreach my $c (values %slot) {
		$c->{stream}->write("$in\r\n");
	}
}



