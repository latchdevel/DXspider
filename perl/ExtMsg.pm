#
# This class is the internal subclass that deals with the external port
# communications for Msg.pm
#
# This is where the cluster handles direct connections coming both in
# and out
#
# $Id$
#
# Copyright (c) 2001 - Dirk Koopman G1TLH
#

package ExtMsg;

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

sub enqueue
{
	my ($conn, $msg) = @_;
	unless ($msg =~ /^[ABZ]/) {
		if ($msg =~ /^E[-\w]+\|([01])/ && $conn->{csort} eq 'telnet') {
			$conn->{echo} = $1;
			if ($1) {
#				$conn->send_raw("\xFF\xFC\x01");
			} else {
#				$conn->send_raw("\xFF\xFB\x01");
			}
		} else {
			$msg =~ s/^[-\w]+\|//;
			push (@{$conn->{outqueue}}, $msg . $conn->{lineend});
		}
	}
}

sub send_raw
{
	my ($conn, $msg) = @_;
    my $sock = $conn->{sock};
    return unless defined($sock);
	push (@{$conn->{outqueue}}, $msg);
	dbg('connect', $msg) unless $conn->{state} eq 'C';
    Msg::set_event_handler ($sock, "write" => sub {$conn->_send(0)});
}

sub dequeue
{
	my $conn = shift;
	my $msg;

	if ($conn->{csort} eq 'ax25' && exists $conn->{msg}) {
		$conn->{msg} =~ s/\cM/\cJ/g;
	}
	if ($conn->{state} eq 'WC') {
		if (exists $conn->{cmd}) {
			if (@{$conn->{cmd}}) {
				dbg('connect', $conn->{msg});
				$conn->_docmd($conn->{msg});
			} 
		}
		if ($conn->{state} eq 'WC' && exists $conn->{cmd} && @{$conn->{cmd}} == 0) {
			$conn->to_connected($conn->{call}, 'O', $conn->{csort});
		}
	} elsif ($conn->{msg} =~ /\cJ/) {
		my @lines =  $conn->{msg} =~ /([^\cM\cJ]*)\cM?\cJ/g;
		if ($conn->{msg} =~ /\cJ$/) {
			delete $conn->{msg};
		} else {
			$conn->{msg} = pop @lines;
		}
		while (defined ($msg = shift @lines)) {
			dbg('connect', $msg) unless $conn->{state} eq 'C';
		
			$msg =~ s/\xff\xfa.*\xff\xf0|\xff[\xf0-\xfe].//g; # remove telnet options
			$msg =~ s/[\x00-\x08\x0a-\x19\x1b-\x1f\x80-\x9f]/./g;         # immutable CSI sequence + control characters
			
			if ($conn->{state} eq 'C') {
				&{$conn->{rproc}}($conn, "I$conn->{call}|$msg");
			} elsif ($conn->{state} eq 'WL' ) {
				$msg = uc $msg;
				if (is_callsign($msg)) {
					$conn->to_connected($msg, 'A', $conn->{csort});
				} else {
					$conn->send_now("Sorry $msg is an invalid callsign");
					$conn->disconnect;
				}
			} elsif ($conn->{state} eq 'WC') {
				if (exists $conn->{cmd} && @{$conn->{cmd}}) {
					$conn->_docmd($msg);
					if ($conn->{state} eq 'WC' && exists $conn->{cmd} &&  @{$conn->{cmd}} == 0) {
						$conn->to_connected($conn->{call}, 'O', $conn->{csort});
					}
				}
			}
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
	$conn->_send_file("$main::data/connected");
	&{$conn->{rproc}}($conn, "$dir$call|$sort");
}

sub new_client {
	my $server_conn = shift;
    my $sock = $server_conn->{sock}->accept();
    my $conn = $server_conn->new($server_conn->{rproc});
	$conn->{sock} = $sock;

    my ($rproc, $eproc) = &{$server_conn->{rproc}} ($conn, $conn->{peerhost} = $sock->peerhost(), $conn->{peerport} = $sock->peerport());
	if ($eproc) {
		$conn->{eproc} = $eproc;
        Msg::set_event_handler ($sock, "error" => $eproc);
	}
    if ($rproc) {
        $conn->{rproc} = $rproc;
        my $callback = sub {$conn->_rcv};
		Msg::set_event_handler ($sock, "read" => $callback);
		# send login prompt
		$conn->{state} = 'WL';
#		$conn->send_raw("\xff\xfe\x01\xff\xfc\x01\ff\fd\x22");
#		$conn->send_raw("\xff\xfa\x22\x01\x01\xff\xf0");
#		$conn->send_raw("\xFF\xFC\x01");
		$conn->_send_file("$main::data/issue");
		$conn->send_raw("login: ");
		$conn->_dotimeout(60);
    } else { 
        $conn->disconnect();
    }
}

sub start_connect
{
	my $call = shift;
	my $fn = shift;
	my $conn = ExtMsg->new(\&main::new_channel); 
	$conn->conns($call);
	
	my $f = new IO::File $fn;
	push @{$conn->{cmd}}, <$f>;
	$f->close;
	$conn->{state} = 'WC';
	$conn->_dotimeout($deftimeout);
	$conn->_docmd;
}

sub _docmd
{
	my $conn = shift;
	my $msg = shift;
	my $cmd;

	while ($cmd = shift @{$conn->{cmd}}) {
		chomp $cmd;
		next if $cmd =~ /^\s*\#/o;
		next if $cmd =~ /^\s*$/o;
		$conn->_doabort($1) if $cmd =~ /^\s*a\w*\s+(.*)/i;
		$conn->_dotimeout($1) if $cmd =~ /^\s*t\w*\s+(\d+)/i;
		$conn->_dolineend($1) if $cmd =~ /^\s*[Ll]\w*\s+\'((?:\\[rn])+)\'/i;
		if ($cmd =~ /^\s*co\w*\s+(\w+)\s+(.*)$/i) {
			unless ($conn->_doconnect($1, $2)) {
				$conn->disconnect;
				@{$conn->{cmd}} = [];    # empty any further commands
				last;
			}  
		}
		if ($cmd =~ /^\s*\'.*\'\s+\'.*\'/i) {
			$conn->_dochat($cmd, $msg);
			last;
		}
		if ($cmd =~ /^\s*cl\w+\s+(.*)/i) {
			$conn->_doclient($1);
			last;
		}
		last if $conn->{state} eq 'E';
	}
}

sub _doconnect
{
	my ($conn, $sort, $line) = @_;
	my $r;

	$sort = lc $sort;
	dbg('connect', "CONNECT sort: $sort command: $line");
	if ($sort eq 'telnet') {
		# this is a straight network connect
		my ($host, $port) = split /\s+/, $line;
		$port = 23 if !$port;
		$r = $conn->connect($host, $port);
		if ($r) {
			dbg('connect', "Connected to $host $port");
		} else {
			dbg('connect', "***Connect Failed to $host $port $!");
		}
	} elsif ($sort eq 'agw') {
		# turn it into an AGW object
		bless $conn, 'AGWMsg';
		$r = $conn->connect($line);
	} elsif ($sort eq 'ax25' || $sort eq 'prog') {
		local $^F = 10000;		# make sure it ain't closed on exec
		my ($a, $b) = IO::Socket->socketpair(AF_UNIX, SOCK_STREAM, PF_UNSPEC);
		if ($a && $b) {
			$r = 1;
			$a->autoflush(1);
			$b->autoflush(1);
			my $pid = fork;
			if (defined $pid) {
				if ($pid) {
					close $b;
					$conn->{sock} = $a;
					$conn->{csort} = $sort;
					$conn->{lineend} = "\cM" if $sort eq 'ax25';
					$conn->{pid} = $pid;
					if ($conn->{rproc}) {
						my $callback = sub {$conn->_rcv};
						Msg::set_event_handler ($a, read => $callback);
					}
					dbg('connect', "started pid: $conn->{pid} as $line");
				} else {
					$^W = 0;
					dbgclose();
					STDIN->close;
					STDOUT->close;
					STDOUT->close;
					*STDIN = IO::File->new_from_fd($b, 'r') or die;
					*STDOUT = IO::File->new_from_fd($b, 'w') or die;
					*STDERR = IO::File->new_from_fd($b, 'w') or die;
					close $a;
					unless ($^O =~ /^MS/) {
#						$SIG{HUP} = 'IGNORE';
						$SIG{HUP} = $SIG{CHLD} = $SIG{TERM} = $SIG{INT} = 'DEFAULT';
						alarm(0);
					}
					exec "$line" or dbg('err', "exec '$line' failed $!");
				} 
			} else {
				dbg('err', "cannot fork");	
				$r = undef;
			}
		} else {
			dbg('err', "no socket pair $!");
		}
	} else {
		dbg('err', "invalid type of connection ($sort)");
	}
	$conn->disconnect unless $r;
	return $r;
}

sub _doabort
{
	my $conn = shift;
	my $string = shift;
	dbg('connect', "abort $string");
	$conn->{abort} = $string;
}

sub _dotimeout
{
	my $conn = shift;
	my $val = shift;
	dbg('connect', "timeout set to $val");
	$conn->{timeout}->del if $conn->{timeout};
	$conn->{timeval} = $val;
	$conn->{timeout} = Timer->new($val, sub{ &_timedout($conn) });
}

sub _dolineend
{
	my $conn = shift;
	my $val = shift;
	dbg('connect', "lineend set to $val ");
	$val =~ s/\\r/\r/g;
	$val =~ s/\\n/\n/g;
	$conn->{lineend} = $val;
}

sub _dochat
{
	my $conn = shift;
	my $cmd = shift;
	my $line = shift;
		
	if ($line) {
		my ($expect, $send) = $cmd =~ /^\s*\'(.*)\'\s+\'(.*)\'/;
		if ($expect) {
			dbg('connect', "expecting: \"$expect\" received: \"$line\"");
			if ($conn->{abort} && $line =~ /\Q$conn->{abort}/i) {
				dbg('connect', "aborted on /$conn->{abort}/");
				$conn->disconnect;
				delete $conn->{cmd};
				return;
			}
			if ($line =~ /\Q$expect/i) {
				dbg('connect', "got: \"$expect\" sending: \"$send\"");
				$conn->send_later("D$conn->{call}|$send");
				delete $conn->{msg}; # get rid any input if a match
				return;
			}
		}
	}
	$conn->{state} = 'WC';
	unshift @{$conn->{cmd}}, $cmd;
}

sub _timedout
{
	my $conn = shift;
	dbg('connect', "timed out after $conn->{timeval} seconds");
	$conn->{timeout}->del;
	delete $conn->{timeout};
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
				$conn->send_raw($_ . $conn->{lineend});
			}
			$f->close;
		}
	}
}
