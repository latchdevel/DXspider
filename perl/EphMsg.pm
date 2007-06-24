#
# This class is the internal subclass that deals with 'Ephmeral'
# communications like: querying http servers and other network
# connected data services and using Msg.pm
#
# An instance of this is setup by a command together with a load
# of callbacks and then runs with a state machine until completion
#
#
#
# Copyright (c) 2001 - Dirk Koopman G1TLH
#

package EphMsg;

use strict;
use Msg;
use DXVars;
use DXUtil;
use DXDebug;
use IO::File;
use IO::Socket;
use IPC::Open3;

use vars qw(@ISA $deftimeout);

@ISA = qw(Msg);
$deftimeout = 60;


sub new
{

}

# we probably won't use the normal format
sub enqueue
{
	my ($conn, $msg) = @_;
	push (@{$conn->{outqueue}}, $msg . $conn->{lineend});
}

sub dequeue
{
	my $conn = shift;
	my $msg;

	if ($conn->{csort} eq 'ax25' && exists $conn->{msg}) {
		$conn->{msg} =~ s/\cM/\cJ/g;
	}

	if ($conn->{state} eq 'WC') {
		$conn->to_connected($conn->{call}, 'O', $conn->{csort});
	}

	if ($conn->{msg} =~ /\cJ/) {
		my @lines =  $conn->{msg} =~ /([^\cM\cJ]*)\cM?\cJ/g;
		if ($conn->{msg} =~ /\cJ$/) {
			delete $conn->{msg};
		} else {
			$conn->{msg} =~ s/([^\cM\cJ]*)\cM?\cJ//g;
		}

		while (defined ($msg = shift @lines)) {
			dbg("connect $conn->{cnum}: $msg") if $conn->{state} ne 'C' && isdbg('connect');

			$msg =~ s/\xff\xfa.*\xff\xf0|\xff[\xf0-\xfe].//g; # remove telnet options

			&{$conn->{rproc}}($conn, $msg);
		}
	}
}

sub to_connected
{
	my ($conn, $call, $dir, $sort) = @_;
	$conn->{state} = 'C';
	$conn->conns($call);
	delete $conn->{cmd};
	$conn->{timeout}->del if $conn->{timeout};
	delete $conn->{timeout};
	$conn->nolinger;
	&{$conn->{rproc}}($conn, "$dir$call|$sort");
}


sub start_connect
{
	my $call = shift;
	my $fn = shift;
	my $conn = ExtMsg->new(\&main::new_channel);
	$conn->{outgoing} = 1;
	$conn->conns($call);

	my $f = new IO::File $fn;
	push @{$conn->{cmd}}, <$f>;
	$f->close;
	$conn->{state} = 'WC';
	$conn->_dotimeout($deftimeout);
}

sub _doconnect
{
	my ($conn, $sort, $line) = @_;
	my $r;

	$sort = lc $sort;			# in this case telnet, ax25 or prog
	dbg("CONNECT $conn->{cnum} sort: $sort command: $line") if isdbg('connect');
	if ($sort eq 'telnet') {
		# this is a straight network connect
		my ($host, $port) = split /\s+/, $line;
		$port = 23 if !$port;
		$r = $conn->connect($host, $port);
		if ($r) {
			dbg("Connected $conn->{cnum} to $host $port") if isdbg('connect');
		} else {
			dbg("***Connect $conn->{cnum} Failed to $host $port $!") if isdbg('connect');
		}
	} elsif ($sort eq 'prog') {
		$r = $conn->start_program($line, $sort);
	} else {
		dbg("invalid type of connection ($sort)");
	}
	$conn->disconnect unless $r;
	return $r;
}

sub _doabort
{
	my $conn = shift;
	my $string = shift;
	dbg("connect $conn->{cnum}: abort $string") if isdbg('connect');
	$conn->{abort} = $string;
}

sub _dotimeout
{
	my $conn = shift;
	my $val = shift;
	dbg("connect $conn->{cnum}: timeout set to $val") if isdbg('connect');
	$conn->{timeout}->del if $conn->{timeout};
	$conn->{timeval} = $val;
	$conn->{timeout} = Timer->new($val, sub{ &_timedout($conn) });
}


sub _timedout
{
	my $conn = shift;
	dbg("connect $conn->{cnum}: timed out after $conn->{timeval} seconds") if isdbg('connect');
	$conn->disconnect;
}

# handle callsign and connection type firtling
sub _doclient
{
	my $conn = shift;
	my $line = shift;
	my @f = split /\s+/, $line;
	my $call = uc $f[0] if $f[0];
	$conn->conns($call);
	$conn->{csort} = $f[1] if $f[1];
	$conn->{state} = 'C';
	&{$conn->{rproc}}($conn, "O$call|$conn->{csort}");
	delete $conn->{cmd};
	$conn->{timeout}->del if $conn->{timeout};
}

sub _send_file
{
	my $conn = shift;
	my $fn = shift;

	if (-e $fn) {
		my $f = new IO::File $fn;
		if ($f) {
			while (<$f>) {
				chomp;
				my $l = $_;
				dbg("connect $conn->{cnum}: $l") if isdbg('connll');
				$conn->send_raw($l . $conn->{lineend});
			}
			$f->close;
		}
	}
}
