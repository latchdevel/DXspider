#
# This has been taken from the 'Advanced Perl Programming' book by Sriram Srinivasan 
#
# I am presuming that the code is distributed on the same basis as perl itself.
#
# I have modified it to suit my devious purposes (Dirk Koopman G1TLH)
#
# $Id$
#

package Msg;

use strict;
use IO::Select;
use IO::Socket;
#use DXDebug;

use vars qw(%rd_callbacks %wt_callbacks $rd_handles $wt_handles $now @timerchain);

%rd_callbacks = ();
%wt_callbacks = ();
$rd_handles   = IO::Select->new();
$wt_handles   = IO::Select->new();
$now = time;
@timerchain = ();

my $blocking_supported = 0;

BEGIN {
    # Checks if blocking is supported
    eval {
        require POSIX; POSIX->import(qw (F_SETFL O_NONBLOCK EAGAIN));
    };
    $blocking_supported = 1 unless $@;
}

#
#-----------------------------------------------------------------
# Generalised initializer

sub new
{
    my ($pkg, $rproc) = @_;
	my $obj = ref($pkg);
	my $class = $obj || $pkg;

    my $conn = {
        rproc => $rproc,
		inqueue => [],
		outqueue => [],
		state => 0,
		lineend => "\r\n",
		csort => 'telnet',
    };

	return bless $conn, $class;
}

#-----------------------------------------------------------------
# Send side routines
sub connect {
    my ($pkg, $to_host, $to_port, $rproc) = @_;

    # Create a new internet socket
    my $sock = IO::Socket::INET->new (
                                      PeerAddr => $to_host,
                                      PeerPort => $to_port,
                                      Proto    => 'tcp',
                                      Reuse    => 1);

    return undef unless $sock;

    # Create a connection end-point object
    my $conn = $pkg;
	unless (ref $pkg) {
		$conn = $pkg->new($rproc);
	}
	$conn->{sock} = $sock;
    
    if ($conn->{rproc}) {
        my $callback = sub {_rcv($conn)};
        set_event_handler ($sock, "read" => $callback);
    }
    return $conn;
}

sub disconnect {
    my $conn = shift;
    my $sock = delete $conn->{sock};
	$conn->{state} = 'E';
	delete $conn->{cmd};
	$conn->{timeout}->del_timer if $conn->{timeout};
	return unless defined($sock);
    set_event_handler ($sock, "read" => undef, "write" => undef);
    shutdown($sock, 3);
	close($sock);
}

sub send_now {
    my ($conn, $msg) = @_;
    $conn->enqueue($msg);
    $conn->_send (1); # 1 ==> flush
}

sub send_later {
    my ($conn, $msg) = @_;
    $conn->enqueue($msg);
    my $sock = $conn->{sock};
    return unless defined($sock);
    set_event_handler ($sock, "write" => sub {$conn->_send(0)});
}

sub enqueue {
    my $conn = shift;
    push (@{$conn->{outqueue}}, $_[0]);
}

sub _send {
    my ($conn, $flush) = @_;
    my $sock = $conn->{sock};
    return unless defined($sock);
    my $rq = $conn->{outqueue};

    # If $flush is set, set the socket to blocking, and send all
    # messages in the queue - return only if there's an error
    # If $flush is 0 (deferred mode) make the socket non-blocking, and
    # return to the event loop only after every message, or if it
    # is likely to block in the middle of a message.

    $flush ? $conn->set_blocking() : $conn->set_non_blocking();
    my $offset = (exists $conn->{send_offset}) ? $conn->{send_offset} : 0;

    while (@$rq) {
        my $msg            = $rq->[0];
		my $mlth           = length($msg);
        my $bytes_to_write = $mlth - $offset;
        my $bytes_written  = 0;
		confess("Negative Length! msg: '$msg' lth: $mlth offset: $offset") if $bytes_to_write < 0;
        while ($bytes_to_write > 0) {
            $bytes_written = syswrite ($sock, $msg,
                                       $bytes_to_write, $offset);
            if (!defined($bytes_written)) {
                if (_err_will_block($!)) {
                    # Should happen only in deferred mode. Record how
                    # much we have already sent.
                    $conn->{send_offset} = $offset;
                    # Event handler should already be set, so we will
                    # be called back eventually, and will resume sending
                    return 1;
                } else {    # Uh, oh
					delete $conn->{send_offset};
                    $conn->handle_send_err($!);
					$conn->disconnect;
                    return 0; # fail. Message remains in queue ..
                }
            }
            $offset         += $bytes_written;
            $bytes_to_write -= $bytes_written;
        }
        delete $conn->{send_offset};
        $offset = 0;
        shift @$rq;
        last unless $flush; # Go back to select and wait
                            # for it to fire again.
    }
    # Call me back if queue has not been drained.
    if (@$rq) {
        set_event_handler ($sock, "write" => sub {$conn->_send(0)});
    } else {
        set_event_handler ($sock, "write" => undef);
    }
    1;  # Success
}

sub _err_will_block {
    if ($blocking_supported) {
        return ($_[0] == EAGAIN());
    }
    return 0;
}
sub set_non_blocking {                        # $conn->set_blocking
    if ($blocking_supported) {
        # preserve other fcntl flags
        my $flags = fcntl ($_[0], F_GETFL(), 0);
        fcntl ($_[0], F_SETFL(), $flags | O_NONBLOCK());
    }
}
sub set_blocking {
    if ($blocking_supported) {
        my $flags = fcntl ($_[0], F_GETFL(), 0);
        $flags  &= ~O_NONBLOCK(); # Clear blocking, but preserve other flags
        fcntl ($_[0], F_SETFL(), $flags);
    }
}

sub handle_send_err {
   # For more meaningful handling of send errors, subclass Msg and
   # rebless $conn.  
   my ($conn, $err_msg) = @_;
   warn "Error while sending: $err_msg \n";
   set_event_handler ($conn->{sock}, "write" => undef);
}

#-----------------------------------------------------------------
# Receive side routines

sub new_server {
    @_ == 4 || die "Msg->new_server (myhost, myport, login_proc\n";
    my ($pkg, $my_host, $my_port, $login_proc) = @_;
	my $self = $pkg->new($login_proc);
	
    $self->{sock} = IO::Socket::INET->new (
                                          LocalAddr => $my_host,
                                          LocalPort => $my_port,
                                          Listen    => 5,
                                          Proto     => 'tcp',
                                          Reuse     => 1);
    die "Could not create socket: $! \n" unless $self->{sock};
    set_event_handler ($self->{sock}, "read" => sub { $self->new_client }  );
	return $self;
}

sub dequeue
{
	my $conn = shift;
	my $msg;
	
	while ($msg = shift @{$conn->{inqueue}}){
		&{$conn->{rproc}}($conn, $msg, $!);
		$! = 0;
	}
}

sub _rcv {                     # Complement to _send
    my $conn = shift; # $rcv_now complement of $flush
    # Find out how much has already been received, if at all
    my ($msg, $offset, $bytes_to_read, $bytes_read);
    my $sock = $conn->{sock};
    return unless defined($sock);

	my @lines;
    $conn->set_non_blocking();
	$bytes_read = sysread ($sock, $msg, 1024, 0);
	if (defined ($bytes_read)) {
		if ($bytes_read > 0) {
			if ($msg =~ /\n/) {
				@lines = split /\r?\n/, $msg;
				$lines[0] = '' unless @lines;
				$lines[0] = $conn->{msg} . $lines[0] if exists $conn->{msg};
				push @lines, ' ' unless @lines;
				if ($msg =~ /\n$/) {
					delete $conn->{msg};
				} else {
					$conn->{msg} = pop @lines;
				}
				push @{$conn->{inqueue}}, @lines if @lines;
			} else {
				$conn->{msg} .= $msg;
			}
		} 
	} else {
		if (_err_will_block($!)) {
			return ; 
		} else {
			$bytes_read = 0;
		}
    }

FINISH:
    if (defined $bytes_read && $bytes_read == 0) {
#		$conn->disconnect();
		&{$conn->{rproc}}($conn, undef, $!);
		delete $conn->{inqueue};
    } else {
		$conn->dequeue;
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
        my $callback = sub {_rcv($conn)};
        set_event_handler ($sock, "read" => $callback);
    } else {  # Login failed
        $conn->disconnect();
    }
}

sub close_server
{
	my $conn = shift;
	set_event_handler ($conn->{sock}, "read" => undef);
	$conn->{sock}->close;
}

#----------------------------------------------------
# Event loop routines used by both client and server

sub set_event_handler {
    shift unless ref($_[0]); # shift if first arg is package name
    my ($handle, %args) = @_;
    my $callback;
    if (exists $args{'write'}) {
        $callback = $args{'write'};
        if ($callback) {
            $wt_callbacks{$handle} = $callback;
            $wt_handles->add($handle);
        } else {
            delete $wt_callbacks{$handle};
            $wt_handles->remove($handle);
        }
    }
    if (exists $args{'read'}) {
        $callback = $args{'read'};
        if ($callback) {
            $rd_callbacks{$handle} = $callback;
            $rd_handles->add($handle);
        } else {
            delete $rd_callbacks{$handle};
            $rd_handles->remove($handle);
       }
    }
}

sub new_timer
{
    my ($pkg, $time, $proc, $recur) = @_;
	my $obj = ref($pkg);
	my $class = $obj || $pkg;
	my $self = bless { t=>$time + time, proc=>$proc }, $class;
	$self->{interval} = $time if $recur;
	push @timerchain, $self;
	return $self;
}

sub del_timer
{
	my $self = shift;
	@timerchain = grep {$_ != $self} @timerchain;
}

sub event_loop {
    my ($pkg, $loop_count, $timeout) = @_; # event_loop(1) to process events once
    my ($conn, $r, $w, $rset, $wset);
    while (1) {
 
       # Quit the loop if no handles left to process
        last unless ($rd_handles->count() || $wt_handles->count());
        
		($rset, $wset) =
            IO::Select->select ($rd_handles, $wt_handles, undef, $timeout);
		$now = time;
		
        foreach $r (@$rset) {
            &{$rd_callbacks{$r}} ($r) if exists $rd_callbacks{$r};
        }
        foreach $w (@$wset) {
            &{$wt_callbacks{$w}}($w) if exists $wt_callbacks{$w};
        }

		# handle things on the timer chain
		for (@timerchain) {
			if ($now >= $_->{t}) {
				&{$_->{proc}}();
				$_->{t} = $now + $_->{interval} if exists $_->{interval};
			}
		}

		# remove dead timers
		@timerchain = grep { $_->{t} > $now } @timerchain;
		
        if (defined($loop_count)) {
            last unless --$loop_count;
        }
    }
}

1;

__END__

