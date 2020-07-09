#
# This class is the internal subclass that deals with the external port
# communications for Msg.pm
#
# This is where the cluster handles direct connections coming both in
# and out
#
#
# Copyright (c) 2001 - Dirk Koopman G1TLH
#
#	Modified Jan 2006 by John Wiseman G8BPQ to support connections to BPQ32 node,
#		and fix pattern matching on 'chat' abort handling
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

sub login
{
	goto &main::login;        # save some writing, this was the default
}

sub enqueue
{
	my ($conn, $msg) = @_;
	unless ($msg =~ /^[ABZ]/) {
		if ($msg =~ m{^E[-\w\/]+\|([01])} && $conn->{csort} eq 'telnet') {
			$conn->{echo} = $1;
			if ($1) {
#				$conn->send_raw("\xFF\xFC\x01");
			} else {
#				$conn->send_raw("\xFF\xFB\x01");
			}
		} else {
			$msg =~ s{^[-\w\/]+\|}{};
			push (@{$conn->{outqueue}}, $msg . $conn->{lineend});
		}
	}
}

sub send_raw
{
	my ($conn, $msg) = @_;
	dbg((ref $conn) . " connect $conn->{cnum}: $msg") if $conn->{state} ne 'C' && isdbg('connect');
	$conn->SUPER::send_raw($msg);
}

sub echo
{
	my $conn = shift;
	$conn->{echo} = shift;
}

sub _rcv
{
    my $conn = shift; # $rcv_now complement of $flush
	my $msg = shift;
    my $sock = $conn->{sock};
    return unless defined($sock);
	return if $conn->{disconnecting};

	if ($conn->{state} eq 'WL' && $conn->{sort} =~ /^I/ && $msg =~ /^PROXY/) {
		my $echo = $conn->{echo};
		$conn->{echo} = 0;
		$conn->SUPER::_rcv($msg);
		$conn->{echo} = $echo;
	} else {
		$conn->SUPER::_rcv($msg);
	}
}

sub dequeue
{
	my $conn = shift;
	my $msg;

	if ($conn->ax25 && exists $conn->{msg}) {
		$conn->{msg} =~ s/\cM/\cJ/g;
	}
	if ($conn->{state} eq 'WC') {
		if (exists $conn->{cmd}) {
			if (@{$conn->{cmd}}) {
				dbg("connect $conn->{cnum}: $conn->{msg}") if isdbg('connect');
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
			$conn->{msg} =~ s/([^\cM\cJ]*)\cM?\cJ//g;
		}
		while (defined ($msg = shift @lines)) {
			dbg("connect $conn->{cnum}: $msg") if $conn->{state} ne 'C' && isdbg('connect');
		
			$msg =~ s/\xff\xfa.*\xff\xf0|\xff[\xf0-\xfe].//g; # remove telnet options
#			$msg =~ s/[\x00-\x08\x0a-\x19\x1b-\x1f\x80-\x9f]/./g;         # immutable CSI sequence + control characters
			
			if ($conn->{state} eq 'C') {
				&{$conn->{rproc}}($conn, "I$conn->{call}|$msg");
			} elsif ($conn->{state} eq 'WL' ) {
				$msg = uc $msg;
				if ($conn->{sort} =~ /^I/ && (my ($ip, $from) = $msg =~ /^PROXY TCP[46] ([\da-fA-F:\.]+) ([\da-fA-F:\.]+)/) ) {
					# SOMEONE appears to have affixed an HA Proxy to my connection
					$ip =~ s|^::ffff:||; # chop off leading pseudo IPV6 stuff on dual stack listeners
					$from =~ s|^::ffff:||;
					if ($from eq $conn->{peerhost}) {
						dbg("ExtMsg: connect - PROXY IP change from '$conn->{peerhost}' -> '$ip'");
						$conn->{peerhost} = $ip;
					} else {
						dbg("ExtMsg: connect - PROXY someone ($from) is trying to spoof '$ip'");
						$conn->send_now("Sorry $msg is an invalid callsign");
						$conn->disconnect;
					}
				} elsif (is_callsign($msg)) {
					if ($main::allowslashcall || $msg !~ m|/|) {
						my $sort = $conn->{csort};
						$sort = 'local' if $conn->{peerhost} =~ /127\.\d+\.\d+\.\d+$/ || $conn->{peerhost} eq '::1';
						my $uref;
						if ($main::passwdreq || ($uref = DXUser::get_current($msg)) && $uref->passwd ) {
							$conn->conns($msg);
							$conn->{state} = 'WP';
							$conn->{decho} = $conn->{echo};
							$conn->{echo} = 0;
							$conn->send_raw('password: ');
						} else {
							$conn->to_connected($msg, 'A', $sort);
						}
					} else {
						$conn->send_now("Sorry $msg is an invalid callsign");
						$conn->disconnect;
					}
				} else {
					$conn->send_now("Sorry $msg is an invalid callsign");
					$conn->disconnect;
				}
			} elsif ($conn->{state} eq 'WP' ) {
				my $uref = DXUser::get_current($conn->{call});
				$msg =~ s/[\r\n]+$//;
				if ($uref && $msg eq $uref->passwd) {
					my $sort = $conn->{csort};
					$conn->{echo} = $conn->{decho};
					delete $conn->{decho};
					$sort = 'local' if $conn->{peerhost} =~ /127\.\d+\.\d+\.\d+$/ || $conn->{peerhost} eq '::1';
					$conn->{usedpasswd} = 1;
					$conn->to_connected($conn->{call}, 'A', $sort);
				} else {
					$conn->send_now("Sorry");
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
	$conn->{csort} = $sort;
	&{$conn->{rproc}}($conn, "$dir$call|$sort");
	$conn->_send_file(localdata("connected")) unless $conn->{outgoing};
}

sub new_client {
	
	my $server_conn = shift;
	my $client = shift;
	my $conn = $server_conn->SUPER::new_client($client);
	# send login prompt
	$conn->{state} = 'WL';
	$conn->_send_file(localdata("issue"));
	$conn->send_raw("login: ");
	$conn->_dotimeout(60);
#	$conn->{echo} = 1;
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
		if ($cmd =~ /^\s*\'([^\']*)\'\s+\'([^\']*)\'/) {
			$conn->_dochat($cmd, $msg, $1, $2);
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
	} elsif ($sort eq 'agw') {
		# turn it into an AGW object
		bless $conn, 'AGWMsg';
		$r = $conn->connect($line);
	} elsif ($sort eq 'bpq') {
		# turn it into an BPQ object
		bless $conn, 'BPQMsg';
		$r = $conn->connect($line);
	} elsif ($sort eq 'ax25' || $sort eq 'prog') {
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

sub _dolineend
{
	my $conn = shift;
	my $val = shift;
	dbg("connect $conn->{cnum}: lineend set to $val ") if isdbg('connect');
	$val =~ s/\\r/\r/g;
	$val =~ s/\\n/\n/g;
	$conn->{lineend} = $val;
}

sub _dochat
{
	my $conn = shift;
	my $cmd = shift;
	my $line = shift;
	my $expect = shift;
	my $send = shift;
		
	if ($line) {
		if ($expect) {
			dbg("connect $conn->{cnum}: expecting: \"$expect\" received: \"$line\"") if isdbg('connect');
			if ($conn->{abort} && $line =~ /$conn->{abort}/i) {
				dbg("connect $conn->{cnum}: aborted on /$conn->{abort}/") if isdbg('connect');
				$conn->disconnect;
				delete $conn->{cmd};
				return;
			}
			if ($line =~ /\Q$expect/i) {
				if (length $send) {
					dbg("connect $conn->{cnum}: got: \"$expect\" sending: \"$send\"") if isdbg('connect');
					$conn->send_later("D$conn->{call}|$send");
				}
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
	eval {$conn->{peerhost} = $conn->{sock}->handle->peerhost} unless $conn->ax25;
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
