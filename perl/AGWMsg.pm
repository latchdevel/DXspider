#
# This class is the internal subclass that deals with AGW Engine connections
#
# The complication here is that there only one 'real' (and from the node's point
# of view, invisible) IP connection. This connection then has multiplexed 
# connections passed down it, a la BPQ native host ports (but not as nicely).
#
# It is a shame that the author has chosen an inherently dangerous binary format
# which is non-framed and has the potential for getting out of sync and not
# being able to recover. Relying on length fields is recipe for disaster (esp.
# for him!). DoS attacks are a wonderful thing....
#
# Also making the user handle the distinction between a level 2 and 4 connection
# and especially Digis, in the way that he has, is a bit of a cop out! If I can
# be arsed to do anything other than straight ax25 connects then it will only
# because I have the 'power of perl' available that avoids me getting 
# terminally bored sorting out other people's sloppyness.
#
# $Id$
#
# Copyright (c) 2001 - Dirk Koopman G1TLH
#

package AGWMsg;

use strict;
use IO::Socket;
use Msg;
use AGWConnect;
use DXDebug;

use vars qw(@ISA $sock @outqueue $send_offset $inmsg $rproc);

@ISA = qw(Msg ExtMsg);
$sock = undef;
@outqueue = ();
$send_offset = 0;
$inmsg = '';
$rproc = undef;

sub init
{
	return unless $enable;
	$rproc = shift;
	
	finish();
	dbg('err', "AGW initialising and connecting to $addr/$port ...");
	$sock = IO::Socket::INET->new(PeerAddr => $addr, PeerPort => $port, Proto=>'tcp');
	unless ($sock) {
		dbg('err', "Cannot connect to AGW Engine at $addr/$port $!");
		return;
	}
	Msg::blocking($sock, 0);
	Msg::set_event_handler($sock, read=>\&_rcv, error=>\&_error);
	
	# send a P frame for the login if required
	if ($login) {
		my $data = pack "a255 a255", $login, $passwd;
		_sendf('P', undef, undef, undef, undef, $data);
	}

	# send:
	# R frame for the release number
	# G frame to ask for ports
	# X frame to say who we are
	_sendf('R');
	_sendf('G');
	_sendf('X', $main::mycall);
	if ($monitor) {
		_sendf('m')
	}
}

sub finish
{
	if ($sock) {
		dbg('err', "AGW ending...");
		for (values %Msg::conns) {
			next unless $_->isa('AGWMsg');
			$_->disconnect;
		}
		# say we are going
		_sendf('x', $main::mycall);
		Msg->sleep(2);
		Msg::set_event_handler($sock, read=>undef, write=>undef, error=>undef);
		$sock->close;
	}
}

sub _sendf
{
	my $sort = shift || confess "need a valid AGW command letter";
	my $from = shift || '';
	my $to   = shift || '';
	my $port = shift || 0;
	my $pid  = shift || 0;
	my $data = shift || '';
	my $len  = 0;
	
	$len = length $data; 
	dbg('agw', "AGW sendf: $sort '${from}'->'${to}' port: $port pid: $pid \"$data\"");
	push @outqueue, pack('C x3 a1 x1 C x1 a10 a10 V x4 a*', $port, $sort, $pid, $from, $to, $len, $data);
	Msg::set_event_handler($sock, write=>\&_send);
}

sub _send 
{
    return unless $sock;

    # If $flush is set, set the socket to blocking, and send all
    # messages in the queue - return only if there's an error
    # If $flush is 0 (deferred mode) make the socket non-blocking, and
    # return to the event loop only after every message, or if it
    # is likely to block in the middle of a message.

    my $offset = $send_offset;

    while (@outqueue) {
        my $msg            = $outqueue[0];
		my $mlth           = length($msg);
        my $bytes_to_write = $mlth - $offset;
        my $bytes_written  = 0;
		confess("Negative Length! msg: '$msg' lth: $mlth offset: $offset") if $bytes_to_write < 0;
        while ($bytes_to_write > 0) {
            $bytes_written = syswrite ($sock, $msg,
                                       $bytes_to_write, $offset);
            if (!defined($bytes_written)) {
                if (Msg::_err_will_block($!)) {
                    # Should happen only in deferred mode. Record how
                    # much we have already sent.
                    $send_offset = $offset;
                    # Event handler should already be set, so we will
                    # be called back eventually, and will resume sending
                    return 1;
                } else {    # Uh, oh
					_error();
                    return 0; # fail. Message remains in queue ..
                }
            }
            $offset         += $bytes_written;
            $bytes_to_write -= $bytes_written;
        }
        $send_offset = $offset = 0;
        shift @outqueue;
        last;  # Go back to select and wait
		       # for it to fire again.
    }

    # Call me back if queue has not been drained.
    if (@outqueue) {
        Msg::set_event_handler ($sock, write => \&_send);
    } else {
        Msg::set_event_handler ($sock, write => undef);
    }
    1;  # Success
}

sub _rcv {                     # Complement to _send
    return unless $sock;
    my ($msg, $offset, $bytes_read);

	$bytes_read = sysread ($sock, $msg, 1024, 0);
	if (defined ($bytes_read)) {
		if ($bytes_read > 0) {
			$inmsg .= $msg;
		} 
	} else {
		if (Msg::_err_will_block($!)) {
			return; 
		} else {
			$bytes_read = 0;
		}
    }

FINISH:
    if (defined $bytes_read && $bytes_read == 0) {
		finish();
    } else {
		_decode() if length $inmsg > 36;
	}
}

sub _error
{
	dbg('agw', "error on AGW connection $addr/$port $!");
	Msg::set_event_handler($sock, read=>undef, write=>undef, error=>undef);
	$sock = undef;
	for (values %Msg::conns) {
		next unless $_->isa('AGWMsg');
		$_->disconnect;
	}
}

sub _decode
{
	return unless $sock;

	# we have at least 36 bytes of data (ugh!)
	my ($port, $sort, $pid, $from, $to, $len) = unpack('C x3 a1 x1 C x1 a10 a10 V x4', $inmsg);
	my $data;

	# do a sanity check on the length
	if ($len > 2000) {
		dbg('err', "AGW: invalid length $len > 2000 received ($sort $port $pid '$from'->'$to')");
		finish();
		return;
	}
	if ($len == 0){
		if (length $inmsg > 36) {
			$inmsg = substr($inmsg, 36);
		} else {
			$inmsg = '';
		}
	} elsif (length $inmsg > $len + 36) {
		$data = substr($inmsg, 36, $len);
		$inmsg = substr($inmsg, $len + 36);
	} elsif (length $inmsg == $len + 36) {
		$data = substr($inmsg, 36);
		$inmsg = '';
	} else {
		# we don't have enough data or something
		# or we have screwed up
		return;
	}

	$data = '' unless defined $data;
	if ($sort eq 'D') {
		$data =~ s/\cR//g;
		dbg('agw', "AGW Data In port: $port pid: $pid '$from'->'$to' length: $len \"$data\"");
		my $conn = Msg->conns($from eq $main::mycall ? $to : $from);
		if ($conn) {
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
			} else {
				&{$conn->{rproc}}($conn, "I$conn->{call}|$data");
			}
		} else {
			dbg('err', "AGW error Unsolicited Data!");
		}
	} elsif ($sort eq 'I' || $sort eq 'S' || $sort eq 'U' || $sort eq 'M') {
		dbg('agw', "AGW Monitor \"$data\"");
	} elsif ($sort eq 'C') {
		dbg('agw', "AGW Connect port: $port pid: $pid '$from'->'$to'");
		my $call = $from eq $main::mycall ? $to : $from;
		my $conn = Msg->conns($call);
		if ($conn) {
			if ($conn->{state} eq 'WC') {
				if (exists $conn->{cmd} && @{$conn->{cmd}}) {
					$conn->_docmd($data);
					if ($conn->{state} eq 'WC' && exists $conn->{cmd} &&  @{$conn->{cmd}} == 0) {
						$conn->to_connected($conn->{call}, 'O', $conn->{csort});
					}
				}
			}
		} else {
			$conn = AGWMsg->new($rproc);
			$conn->{agwpid} = $pid;
			$conn->{agwport} = $port;
			$conn->{lineend} = "\cR";
			$conn->to_connected($call, 'A', $conn->{csort} = 'ax25');
		}
	} elsif ($sort eq 'd') {
		dbg('agw', "AGW '$from'->'$to' Disconnected");
		my $conn = Msg->conns($from eq $main::mycall ? $to : $from);
		$conn->in_disconnect if $conn;
	} elsif ($sort eq 'y') {
		my ($frames) = unpack "V", $data;
		dbg('agw', "AGW Frames Outstanding on port $port = $frames");
		my $conn = Msg->conns($from);
		$conn->{oframes} = $frames if $conn;
	} elsif ($sort eq 'Y') {
		my ($frames) = unpack "V", $data;
		dbg('agw', "AGW Frames Outstanding on circuit '$from'->'$to' = $frames");
		my $conn = Msg->conns($from eq $main::mycall ? $to : $from);
		$conn->{oframes} = $frames if $conn;
	} elsif ($sort eq 'X') {
		my ($r) = unpack "C", $data;
		$r = $r ? "Successful" : "Failed";
		dbg('err', "AGW Register $from $r");
		finish() unless $r;
	} elsif ($sort eq 'R') {
		my ($major, $minor) = unpack "v x2 v x2", $data;
		dbg('agw', "AGW Version $major.$minor");
	} elsif ($sort eq 'G') {
		my @ports = split /;/, $data;
		dbg('agw', "AGW $ports[0] Ports available");
		my $n = shift @ports;
		pop @ports while @ports > $n;
		for (@ports) {
			next unless $_;
			dbg('agw', "AGW Port: $_");
		}
	} else {
		dbg('agw', "AGW decode $sort port: $port pid: $pid '$from'->'$to' length: $len \"$data\"");
	}
}

sub in_disconnect
{
	my $conn = shift;
	$conn->SUPER->disconnect;
}

sub disconnect
{
	my $conn = shift;
	_sendf('d', $main::mycall, $conn->{call}, $conn->{agwport});
	$conn->SUPER->disconnect;
}

sub enqueue
{
	my ($conn, $msg) = @_;
	if ($msg =~ /^[D]/) {
		$msg =~ s/^[-\w]+\|//;
		_sendf('D', $main::mycall, $conn->{call}, $conn->{agwport}, $conn->{agwpid}, $msg . $conn->{lineend});
	}
}
1;

