#
# This class is the internal subclass that deals with UDP Engine connections
#
# The complication here is that there may be just a multicast address with
# one shared connection or there may be several 'connections' which have no
# real defined start or end.
#
# This class will morph into (and is the test bed for) Multicasts
#
# $Id$
#
# Copyright (c) 2002 - Dirk Koopman G1TLH
#

package UDPMsg;

use strict;
use IO::Socket;
use Msg;
use DXDebug;

use vars qw(@ISA @sock @outqueue $send_offset $inmsg $rproc $noports 
			%circuit $total_in $total_out $enable);

@ISA = qw(Msg ExtMsg);
@sock = ();
@outqueue = ();
$send_offset = 0;
$inmsg = '';
$rproc = undef;
$noports = 0;
%circuit = ();
$total_in = $total_out = 0;

use vars qw($VERSION $BRANCH);
$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /\d+\.\d+\.(\d+)\.(\d+)/,(0,0));
$main::build += $VERSION;
$main::branch += $BRANCH;

sub init
{
	return unless $enable;
	return unless @main::listen;
	
	$rproc = shift;
	
	foreach my $sock (@main::listen) {
		dbg("UDP initialising and connecting to $_->[0]/$_->[1] ...");
		$sock = IO::Socket::INET->new(LocalAddr => $_->[0], LocalPort => $_->[1], Proto=>'udp', Type => SOCK_DGRAM);
		
		unless ($sock) {
			dbg("Cannot connect to UDP Engine at $_->[0]/$_->[1] $!");
			return;
		}
		Msg::blocking($sock, 0);
		Msg::set_event_handler($sock, read=>\&_rcv, error=>\&_error);
	}
	finish();
}

my $finishing = 0;

sub finish
{
	return if $finishing;
	foreach my $sock (@sock) {
		$finishing = 1;
		dbg("UDP ending...");
		for (values %circuit) {
			&{$_->{eproc}}() if $_->{eproc};
			$_->disconnect;
		}
		Msg::set_event_handler($sock, read=>undef, write=>undef, error=>undef);
		$sock->close;
	}
}

sub active
{
	return scalar @sock;
}

sub _sendf
{
	my $sort = shift || confess "need a valid UDP command letter";
	my $from = shift || '';
	my $to   = shift || '';
	my $port = shift || 0;
	my $pid  = shift || 0;
	my $data = shift || '';
	my $len  = 0;
	
	$len = length $data; 

	# do it

	# Msg::set_event_handler($sock, write=>\&_send);
}

sub _send 
{
    return unless @sock;

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
#            $bytes_written = syswrite ($sock, $msg,
#                                       $bytes_to_write, $offset);
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
			if (isdbg('raw')) {
				dbgdump('raw', "UDP send $bytes_written: ", $msg);
			}
            $total_out      += $bytes_written;
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
#        Msg::set_event_handler ($sock, write => \&_send);
    } else {
#        Msg::set_event_handler ($sock, write => undef);
    }
    1;  # Success
}

sub _rcv {                     # Complement to _send
    return unless @sock;

    my ($msg, $offset, $bytes_read);

#	$bytes_read = sysread ($sock, $msg, 1024, 0);
	if (defined ($bytes_read)) {
		if ($bytes_read > 0) {
            $total_in += $bytes_read;
			$inmsg .= $msg;
			if (isdbg('raw')) {
				dbgdump('raw', "UDP read $bytes_read: ", $msg);
			}
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
		_decode() if length $inmsg >= 36;
	}
}

sub _error
{
#	dbg("error on UDP connection $addr/$port $!");
#	Msg::set_event_handler($sock, read=>undef, write=>undef, error=>undef);
#	$sock = undef;
	for (%circuit) {
		&{$_->{eproc}}() if $_->{eproc};
		$_->disconnect;
	}
}

sub _decode
{
	return unless @sock;

}

sub _find
{
	my $call = shift;
	return $circuit{$call};
}

sub connect
{
	my ($conn, $line) = @_;
	
	my ($port, $call) = split /\s+/, $line;
	$conn->{udppid} = ord "\xF0";
	$conn->{udpport} = $port - 1;
	$conn->{lineend} = "\cM";
	$conn->{incoming} = 0;
	$conn->{csort} = 'ax25';
	$conn->{udpcall} = uc $call;
	$circuit{$conn->{udpcall}} = $conn; 
	$conn->{state} = 'WC';
	return 1;
}

sub in_disconnect
{
	my $conn = shift;
	delete $circuit{$conn->{udpcall}}; 
	$conn->SUPER::disconnect;
}

sub disconnect
{
	my $conn = shift;
	delete $circuit{$conn->{udpcall}}; 
	if ($conn->{incoming}) {
	}
	$conn->SUPER::disconnect;
}

sub enqueue
{
	my ($conn, $msg) = @_;
	if ($msg =~ /^D/) {
		$msg =~ s/^[-\w]+\|//;
		my $len = length($msg) + 1; 
		dbg("UDP Data Out port: $conn->{udpport} pid: $conn->{udppid} '$main::mycall'->'$conn->{udpcall}' length: $len \"$msg\"") if isdbg('udp');
	}
}

sub process
{
	return unless @sock;
}

1;

