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

use vars qw($VERSION $BRANCH);
$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /\d+\.\d+\.(\d+)\.(\d+)/ ) || 0;
$main::build += $VERSION;
$main::branch += $BRANCH;

use IO::Select;
use IO::Socket;
use DXDebug;
use Timer;

use vars qw(%rd_callbacks %wt_callbacks %er_callbacks $rd_handles $wt_handles $er_handles $now %conns $noconns $blocking_supported $cnum);

%rd_callbacks = ();
%wt_callbacks = ();
%er_callbacks = ();
$rd_handles   = IO::Select->new();
$wt_handles   = IO::Select->new();
$er_handles   = IO::Select->new();

$now = time;

BEGIN {
    # Checks if blocking is supported
    eval {
        require POSIX; POSIX->import(qw(O_NONBLOCK F_SETFL F_GETFL))
    };
	if ($@ || $main::is_win) {
#		print STDERR "POSIX Blocking *** NOT *** supported $@\n";
		$blocking_supported = 0;
	} else {
		$blocking_supported = 1;
#		print STDERR "POSIX Blocking enabled\n";
	}


	# import as many of these errno values as are available
	eval {
		require Errno; Errno->import(qw(EAGAIN EINPROGRESS EWOULDBLOCK));
	};
}

my $w = $^W;
$^W = 0;
my $eagain = eval {EAGAIN()};
my $einprogress = eval {EINPROGRESS()};
my $ewouldblock = eval {EWOULDBLOCK()};
$^W = $w;
$cnum = 0;


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
		timeval => 60,
		blocking => 0,
		cnum => (($cnum < 999) ? (++$cnum) : ($cnum = 1)),
    };

	$noconns++;
	
	dbg("Connection created ($noconns)") if isdbg('connll');
	return bless $conn, $class;
}

sub set_error
{
	my $conn = shift;
	my $callback = shift;
	$conn->{eproc} = $callback;
	set_event_handler($conn->{sock}, error => $callback) if exists $conn->{sock};
}

sub set_rproc
{
	my $conn = shift;
	my $callback = shift;
	$conn->{rproc} = $callback;
}

sub blocking
{
	return unless $blocking_supported;
	
	my $flags = fcntl ($_[0], F_GETFL, 0);
	if ($_[1]) {
		$flags &= ~O_NONBLOCK;
	} else {
		$flags |= O_NONBLOCK;
	}
	fcntl ($_[0], F_SETFL, $flags);
}

# save it
sub conns
{
	my $pkg = shift;
	my $call = shift;
	my $ref;
	
	if (ref $pkg) {
		$call = $pkg->{call} unless $call;
		return undef unless $call;
		dbg("changing $pkg->{call} to $call") if isdbg('connll') && exists $pkg->{call} && $call ne $pkg->{call};
		delete $conns{$pkg->{call}} if exists $pkg->{call} && exists $conns{$pkg->{call}} && $pkg->{call} ne $call; 
		$pkg->{call} = $call;
		$ref = $conns{$call} = $pkg;
		dbg("Connection $pkg->{cnum} $call stored") if isdbg('connll');
	} else {
		$ref = $conns{$call};
	}
	return $ref;
}

# this is only called by any dependent processes going away unexpectedly
sub pid_gone
{
	my ($pkg, $pid) = @_;
	
	my @pid = grep {$_->{pid} == $pid} values %conns;
	foreach my $p (@pid) {
		&{$p->{eproc}}($p, "$pid has gorn") if exists $p->{eproc};
		$p->disconnect;
	}
}

#-----------------------------------------------------------------
# Send side routines
sub connect {
    my ($pkg, $to_host, $to_port, $rproc) = @_;

    # Create a connection end-point object
    my $conn = $pkg;
	unless (ref $pkg) {
		$conn = $pkg->new($rproc);
	}
	$conn->{peerhost} = $to_host;
	$conn->{peerport} = $to_port;
	$conn->{sort} = 'Outgoing';
	
    # Create a new internet socket
    my $sock = IO::Socket::INET->new();
    return undef unless $sock;
	
	my $proto = getprotobyname('tcp');
	$sock->socket(AF_INET, SOCK_STREAM, $proto) or return undef;
	
	blocking($sock, 0);
	$conn->{blocking} = 0;

	my $ip = gethostbyname($to_host);
#	my $r = $sock->connect($to_port, $ip);
	my $r = connect($sock, pack_sockaddr_in($to_port, $ip));
	return undef unless $r || _err_will_block($!);
	
	$conn->{sock} = $sock;
    
    if ($conn->{rproc}) {
        my $callback = sub {$conn->_rcv};
        set_event_handler ($sock, read => $callback);
    }
    return $conn;
}

sub disconnect {
    my $conn = shift;
	return if exists $conn->{disconnecting};

	$conn->{disconnecting} = 1;
    my $sock = delete $conn->{sock};
	$conn->{state} = 'E';
	$conn->{timeout}->del if $conn->{timeout};

	# be careful to delete the correct one
	my $call;
	if ($call = $conn->{call}) {
		my $ref = $conns{$call};
		delete $conns{$call} if $ref && $ref == $conn;
	}
	$call ||= 'unallocated';
	dbg("Connection $conn->{cnum} $call disconnected") if isdbg('connll');
	
	# get rid of any references
	for (keys %$conn) {
		if (ref($conn->{$_})) {
			delete $conn->{$_};
		}
	}

	if (defined($sock)) {
		set_event_handler ($sock, read => undef, write => undef, error => undef);
		shutdown($sock, 3);
		close($sock);
	}
	
	unless ($main::is_win) {
		kill 'TERM', $conn->{pid} if exists $conn->{pid};
	}

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
    set_event_handler ($sock, write => sub {$conn->_send(0)});
}

sub enqueue {
    my $conn = shift;
    push (@{$conn->{outqueue}}, defined $_[0] ? $_[0] : '');
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

	if ($conn->{blocking} != $flush) {
		blocking($sock, $flush);
		$conn->{blocking} = $flush;
	}
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
					&{$conn->{eproc}}($conn, $!) if exists $conn->{eproc};
					$conn->disconnect;
                    return 0; # fail. Message remains in queue ..
                }
            } elsif (isdbg('raw')) {
				my $call = $conn->{call} || 'none';
				dbgdump('raw', "$call send $bytes_written: ", $msg);
			}
            $offset         += $bytes_written;
            $bytes_to_write -= $bytes_written;
        }
        delete $conn->{send_offset};
        $offset = 0;
        shift @$rq;
        #last unless $flush; # Go back to select and wait
                            # for it to fire again.
    }
    # Call me back if queue has not been drained.
    unless (@$rq) {
        set_event_handler ($sock, write => undef);
		if (exists $conn->{close_on_empty}) {
			&{$conn->{eproc}}($conn, undef) if exists $conn->{eproc};
			$conn->disconnect; 
		}
    }
    1;  # Success
}

sub dup_sock
{
	my $conn = shift;
	my $oldsock = $conn->{sock};
	my $rc = $rd_callbacks{$oldsock};
	my $wc = $wt_callbacks{$oldsock};
	my $ec = $er_callbacks{$oldsock};
	my $sock = $oldsock->new_from_fd($oldsock, "w+");
	if ($sock) {
		set_event_handler($oldsock, read=>undef, write=>undef, error=>undef);
		$conn->{sock} = $sock;
		set_event_handler($sock, read=>$rc, write=>$wc, error=>$ec);
		$oldsock->close;
	}
}

sub _err_will_block {
	return 0 unless $blocking_supported;
	return ($_[0] == $eagain || $_[0] == $ewouldblock || $_[0] == $einprogress);
}

sub close_on_empty
{
	my $conn = shift;
	$conn->{close_on_empty} = 1;
}

#-----------------------------------------------------------------
# Receive side routines

sub new_server {
    @_ == 4 || die "Msg->new_server (myhost, myport, login_proc\n";
    my ($pkg, $my_host, $my_port, $login_proc) = @_;
	my $self = $pkg->new($login_proc);
	
    $self->{sock} = IO::Socket::INET->new (
                                          LocalAddr => "$my_host:$my_port",
#                                          LocalPort => $my_port,
                                          Listen    => SOMAXCONN,
                                          Proto     => 'tcp',
                                          Reuse => 1);
    die "Could not create socket: $! \n" unless $self->{sock};
    set_event_handler ($self->{sock}, read => sub { $self->new_client }  );
	return $self;
}

sub nolinger
{
	my $conn = shift;
	setsockopt($conn->{sock}, SOL_SOCKET, SO_LINGER, pack("ll", 0, 0)) or confess "setsockopt: $!";
}

sub dequeue
{
	my $conn = shift;

	if ($conn->{msg} =~ /\n/) {
		my @lines = split /\r?\n/, $conn->{msg};
		if ($conn->{msg} =~ /\n$/) {
			delete $conn->{msg};
		} else {
			$conn->{msg} = pop @lines;
		}
		for (@lines) {
			&{$conn->{rproc}}($conn, defined $_ ? $_ : '');
		}
	}
}

sub _rcv {                     # Complement to _send
    my $conn = shift; # $rcv_now complement of $flush
    # Find out how much has already been received, if at all
    my ($msg, $offset, $bytes_to_read, $bytes_read);
    my $sock = $conn->{sock};
    return unless defined($sock);

	my @lines;
	if ($conn->{blocking}) {
		blocking($sock, 0);
		$conn->{blocking} = 0;
	}
	$bytes_read = sysread ($sock, $msg, 1024, 0);
	if (defined ($bytes_read)) {
		if ($bytes_read > 0) {
			if (isdbg('raw')) {
				my $call = $conn->{call} || 'none';
				dbgdump('raw', "$call read $bytes_read: ", $msg);
			}
			if ($conn->{echo}) {
				my @ch = split //, $msg;
				my $out;
				for (@ch) {
					if (/[\cH\x7f]/) {
						$out .= "\cH \cH";
						$conn->{msg} =~ s/.$//;
					} else {
						$out .= $_;
						$conn->{msg} .= $_;
					}
				}
				if (defined $out) {
					set_event_handler ($sock, write => sub{$conn->_send(0)});
					push @{$conn->{outqueue}}, $out;
				}
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
		&{$conn->{eproc}}($conn, $!) if exists $conn->{eproc};
		$conn->disconnect;
    } else {
		unless ($conn->{disable_read}) {
			$conn->dequeue if exists $conn->{msg};
		}
	}
}

sub new_client {
	my $server_conn = shift;
    my $sock = $server_conn->{sock}->accept();
	if ($sock) {
		my $conn = $server_conn->new($server_conn->{rproc});
		$conn->{sock} = $sock;
		blocking($sock, 0);
		$conn->nolinger;
		$conn->{blocking} = 0;
		my ($rproc, $eproc) = &{$server_conn->{rproc}} ($conn, $conn->{peerhost} = $sock->peerhost(), $conn->{peerport} = $sock->peerport());
		$conn->{sort} = 'Incoming';
		if ($eproc) {
			$conn->{eproc} = $eproc;
			set_event_handler ($sock, error => $eproc);
		}
		if ($rproc) {
			$conn->{rproc} = $rproc;
			my $callback = sub {$conn->_rcv};
			set_event_handler ($sock, read => $callback);
		} else {  # Login failed
			&{$conn->{eproc}}($conn, undef) if exists $conn->{eproc};
			$conn->disconnect();
		}
	} else {
		dbg("Msg: error on accept ($!)") if isdbg('err');
	}
}

sub close_server
{
	my $conn = shift;
	set_event_handler ($conn->{sock}, read => undef, write => undef, error => undef );
	$conn->{sock}->close;
}

# close all clients (this is for forking really)
sub close_all_clients
{
	foreach my $conn (values %conns) {
		$conn->disconnect;
	}
}

sub disable_read
{
	my $conn = shift;
	set_event_handler ($conn->{sock}, read => undef);
	return $_[0] ? $conn->{disable_read} = $_[0] : $_[0];
}

#
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
    if (exists $args{'error'}) {
        $callback = $args{'error'};
        if ($callback) {
            $er_callbacks{$handle} = $callback;
            $er_handles->add($handle);
        } else {
            delete $er_callbacks{$handle};
            $er_handles->remove($handle);
       }
    }
}

sub event_loop {
    my ($pkg, $loop_count, $timeout) = @_; # event_loop(1) to process events once
    my ($conn, $r, $w, $e, $rset, $wset, $eset);
    while (1) {
 
       # Quit the loop if no handles left to process
        last unless ($rd_handles->count() || $wt_handles->count());
        
		($rset, $wset, $eset) = IO::Select->select($rd_handles, $wt_handles, $er_handles, $timeout);
		
        foreach $e (@$eset) {
            &{$er_callbacks{$e}}($e) if exists $er_callbacks{$e};
        }
        foreach $r (@$rset) {
            &{$rd_callbacks{$r}}($r) if exists $rd_callbacks{$r};
        }
        foreach $w (@$wset) {
            &{$wt_callbacks{$w}}($w) if exists $wt_callbacks{$w};
        }

		Timer::handler;
		
        if (defined($loop_count)) {
            last unless --$loop_count;
        }
    }
}

sub sleep
{
	my ($pkg, $interval) = @_;
	my $now = time;
	while (time - $now < $interval) {
		$pkg->event_loop(10, 0.01);
	}
}

sub DESTROY
{
	my $conn = shift;
	my $call = $conn->{call} || 'unallocated';
	my $host = $conn->{peerhost} || '';
	my $port = $conn->{peerport} || '';
	dbg("Connection $conn->{cnum} $call [$host $port] being destroyed") if isdbg('connll');
	$noconns--;
}

1;

__END__

