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
	
	while (@{$conn->{inqueue}}){
		$msg = shift @{$conn->{inqueue}};
		dbg('connect', $msg) unless $conn->{state} eq 'C';
		
		$msg =~ s/\xff\xfa.*\xff\xf0|\xff[\xf0-\xfe].//g; # remove telnet options
		$msg =~ s/[\x00-\x08\x0a-\x1f\x80-\x9f]/./g;         # immutable CSI sequence + control characters

		if ($conn->{state} eq 'C') {
			&{$conn->{rproc}}($conn, "I$conn->{call}|$msg", $!);
			$! = 0;
		} elsif ($conn->{state} eq 'WL' ) {
			$msg = uc $msg;
			if (is_callsign($msg)) {
				_send_file($conn, "$main::data/connected");
				$conn->{call} = $msg;
				&{$conn->{rproc}}($conn, "A$conn->{call}|telnet");
				$conn->{state} = 'C';
			} else {
				$conn->send_now("Sorry $msg is an invalid callsign");
				$conn->disconnect;
			}
		} elsif ($conn->{state} eq 'WC') {
			if (exists $conn->{cmd} && @{$conn->{cmd}}) {
				$conn->_docmd($msg);
				if ($conn->{state} eq 'WC' && exists $conn->{cmd} &&  @{$conn->{cmd}} == 0) {
					$conn->{state} = 'C';
					&{$conn->{rproc}}($conn, "O$conn->{call}|telnet");
					delete $conn->{cmd};
					$conn->{timeout}->del_timer if $conn->{timeout};
				}
			}
		}
	}
	if ($conn->{msg} && $conn->{state} eq 'WC' && exists $conn->{cmd} && @{$conn->{cmd}}) {
		dbg('connect', $conn->{msg});
		$conn->_docmd($conn->{msg});
		if ($conn->{state} eq 'WC' && exists $conn->{cmd} && @{$conn->{cmd}} == 0) {
			$conn->{state} = 'C';
			&{$conn->{rproc}}($conn, "O$conn->{call}|telnet");
			delete $conn->{cmd};
			$conn->{timeout}->del_timer if $conn->{timeout};
		}
	}
}

sub new_client {
	my $server_conn = shift;
    my $sock = $server_conn->{sock}->accept();
    my $conn = $server_conn->new($server_conn->{rproc});
	$conn->{sock} = $sock;

    my $rproc = &{$server_conn->{rproc}} ($conn, $sock->peerhost(), $sock->peerport());
    if ($rproc) {
        $conn->{rproc} = $rproc;
        my $callback = sub {$conn->_rcv};
		Msg::set_event_handler ($sock, "read" => $callback);
		# send login prompt
		$conn->{state} = 'WL';
#		$conn->send_raw("\xff\xfe\x01\xff\xfc\x01\ff\fd\x22");
#		$conn->send_raw("\xff\xfa\x22\x01\x01\xff\xf0");
#		$conn->send_raw("\xFF\xFC\x01");
		_send_file($conn, "$main::data/issue");
		$conn->send_raw("login: ");
    } else { 
        $conn->disconnect();
    }
}

sub start_connect
{
	my $call = shift;
	my $fn = shift;
	my $conn = ExtMsg->new(\&main::rec); 
	$conn->{call} = $call;
	
	my $f = new IO::File $fn;
	push @{$conn->{cmd}}, <$f>;
	$f->close;
	push @main::outstanding_connects, {call => $call, conn => $conn};
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
	unless (exists $conn->{cmd} && @{$conn->{cmd}}) {
		@main::outstanding_connects = grep {$_->{call} ne $conn->{call}} @main::outstanding_connects;
	}
}

sub _doconnect
{
	my ($conn, $sort, $line) = @_;
	my $r;
	
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
	} elsif ($sort eq 'ax25' || $sort eq 'prog') {
		;
	} else {
		dbg('err', "invalid type of connection ($sort)");
		$conn->disconnect;
	}
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
	$conn->{timeout}->del_timer if $conn->{timeout};
	$conn->{timeout} = ExtMsg->new_timer($val, sub{ _timeout($conn); });
	$conn->{timeval} = $val;
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
			if ($conn->{abort} && $line =~ /$conn->{abort}/i) {
				dbg('connect', "aborted on /$conn->{abort}/");
				$conn->disconnect;
				delete $conn->{cmd};
				return;
			}
			if ($line =~ /$expect/i) {
				dbg('connect', "got: \"$expect\" sending: \"$send\"");
				$conn->send_later($send);
				return;
			}
		}
	}
	$conn->{state} = 'WC';
	unshift @{$conn->{cmd}}, $cmd;
}

sub _timeout
{
	my $conn = shift;
	dbg('connect', "timed out after $conn->{timeval} seconds");
	$conn->disconnect;
	@main::outstanding_connects = grep {$_->{call} ne $conn->{call}} @main::outstanding_connects;
}

# handle callsign and connection type firtling
sub _doclient
{
	my $conn = shift;
	my $line = shift;
	my @f = split /\s+/, $line;
	$conn->{call} = uc $f[0] if $f[0];
	$conn->{csort} = $f[1] if $f[1];
	$conn->{state} = 'C';
	&{$conn->{rproc}}($conn, "O$conn->{call}|telnet");
	delete $conn->{cmd};
	$conn->{timeout}->del_timer if $conn->{timeout};
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
	$! = undef;
}
