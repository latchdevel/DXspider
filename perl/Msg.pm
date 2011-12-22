#
# This has been taken from the 'Advanced Perl Programming' book by Sriram Srinivasan 
#
# I am presuming that the code is distributed on the same basis as perl itself.
#
# I have modified it to suit my devious purposes (Dirk Koopman G1TLH)
#
#
#

package Msg;

use strict;

use DXUtil;

use AnyEvent;
use AnyEvent::Handle;
use AnyEvent::Socket;

use DXDebug;
use Timer;

use vars qw(%conns $noconns $cnum $total_in $total_out);

$total_in = $total_out = 0;
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
}

sub set_rproc
{
	my $conn = shift;
	my $callback = shift;
	$conn->{rproc} = $callback;
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

sub ax25
{
	my $conn = shift;
	return $conn->{csort} eq 'ax25';
}

sub peerhost
{
	my $conn = shift;
	$conn->{peerhost} ||= 'ax25' if $conn->ax25;
	$conn->{peerhost} ||= $conn->{sock}->peerhost if $conn->{sock} && $conn->{sock}->isa('IO::Socket::INET');
	$conn->{peerhost} ||= 'UNKNOWN';
	return $conn->{peerhost};
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
	
	my $sock = AnyEvent::Handle->new(

		connect => [$to_host, $to_port],

#		on_connect => sub {my $h = shift; $conn->{peerhost} = $h->handle->peername;},

		on_eof => sub {$conn->disconnect},

		on_error => sub {$conn->disconnect},

		keepalive => 1,

		linger => 0,
	);
	
	$conn->{sock} = $sock;
	$sock->on_read(sub{$conn->_rcv});

    return $conn;
}

sub start_program
{
	my ($conn, $line, $sort) = @_;
	my $pid;
	
#	local $^F = 10000;		# make sure it ain't closed on exec
#	my ($a, $b) = $io_socket->socketpair(AF_UNIX, SOCK_STREAM, PF_UNSPEC);
#	if ($a && $b) {
#		$a->autoflush(1);
#		$b->autoflush(1);
#		$pid = fork;
#		if (defined $pid) {
#			if ($pid) {
#				close $b;
#				$conn->{sock} = $a;
#				$conn->{csort} = $sort;
#				$conn->{lineend} = "\cM" if $sort eq 'ax25';
#				$conn->{pid} = $pid;
#				if ($conn->{rproc}) {
#					my $callback = sub {$conn->_rcv};
#					Msg::set_event_handler ($a, read => $callback);
#				}
#				dbg("connect $conn->{cnum}: started pid: $conn->{pid} as $line") if isdbg('connect');
#			} else {
#				$^W = 0;
#				dbgclose();
#				STDIN->close;
#				STDOUT->close;
#				STDOUT->close;
#				*STDIN = IO::File->new_from_fd($b, 'r') or die;
#				*STDOUT = IO::File->new_from_fd($b, 'w') or die;
#				*STDERR = IO::File->new_from_fd($b, 'w') or die;
#				close $a;
#				unless ($main::is_win) {
#					#						$SIG{HUP} = 'IGNORE';
#					$SIG{HUP} = $SIG{CHLD} = $SIG{TERM} = $SIG{INT} = 'DEFAULT';
#					alarm(0);
#				}
#				exec "$line" or dbg("exec '$line' failed $!");
#			}
#		} else {
#			dbg("cannot fork for $line");
#		}
#	} else {
#		dbg("no socket pair $! for $line");
#	}
	return $pid;
}

sub disconnect 
{
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
		shutdown($sock->{fh}, 2);
		$sock->destroy;
	}
	
	unless ($main::is_win) {
		kill 'TERM', $conn->{pid} if exists $conn->{pid};
	}
}

sub _send_stuff
{
    my $conn = shift;
	my $rq = $conn->{outqueue};
	my $sock = $conn->{sock};

	while (@$rq) {
		my $data = shift @$rq;
		my $lth = length $data;
		my $call = $conn->{call} || 'none';
		if (isdbg('raw')) {
			if (isdbg('raw')) {
				dbgdump('raw', "$call send $lth: ", $lth);
			}
		}
		if (defined $sock && !$sock->destroyed) {
			$sock->push_write($data);
			$total_out = $lth;
		} else {
			dbg("_send_stuff $call ending data ignored: $data");
		}
	}
}

sub send_later {
    my ($conn, $msg) = @_;
	my $rq = $conn->{outqueue};
	my $sock = $conn->{sock};

	# this is done like this because enqueueing may be going on independently of
	# sending (whether later or now)
    $conn->enqueue($msg);
	_send_stuff($conn)
}

sub send_now { goto &send_later; }

sub send_raw
{
    my ($conn, $msg) = @_;
	push @{$conn->{outqueue}}, $msg;
	_send_stuff($conn);
}

sub enqueue {
    my $conn = shift;
    push (@{$conn->{outqueue}}, defined $_[0] ? $_[0] : '');
}

sub _err_will_block {
	return 0;
}

sub close_on_empty
{
	my $conn = shift;
	$conn->{sock}->on_drain(sub {$conn->disconnect;});
}

#-----------------------------------------------------------------
# Receive side routines

sub new_server {
    @_ == 4 || die "Msg->new_server (myhost, myport, login_proc\n";
    my ($pkg, $my_host, $my_port, $login_proc) = @_;
	my $self = $pkg->new($login_proc);
	
    $self->{sock} = tcp_server $my_host, $my_port, sub { $self->new_client(@_); }, sub { return 256; };
    die "Could not create socket: $! \n" unless $self->{sock};
	return $self;
}


sub nolinger
{
	my $conn = shift;
	my $sock = $conn->{sock};
#	$sock->linger(0);
#	$sock->keepalive(1);
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
	$msg = $sock->{rbuf};
	$bytes_read = length $msg || 0;
	$sock->{rbuf} = '';

	if ($bytes_read > 0) {
		$total_in += $bytes_read;
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
				$conn->send_now($out);
			}
		} else {
			$conn->{msg} .= $msg;
		}
	}

	unless ($conn->{disable_read}) {
		$conn->dequeue if exists $conn->{msg};
	}
}

sub new_client {
	my $server_conn = shift;
	my $sock = shift;
	my $peerhost = shift;
	my $peerport = shift;
	if ($sock) {
		my $conn = $server_conn->new($server_conn->{rproc});
		$conn->{sock} = AnyEvent::Handle->new(

            fh => $sock,

		    on_eof => sub {$conn->disconnect},

		    on_error => sub {$conn->disconnect},

		    keepalive => 1,

		    linger => 0,
	    );
		$conn->{blocking} = 0;
		my ($rproc, $eproc) = &{$server_conn->{rproc}} ($conn, $conn->{peerhost} = $peerhost, $conn->{peerport} = $peerport);
		dbg("accept $conn->{cnum} from $conn->{peerhost} $conn->{peerport}") if isdbg('connll');
		$conn->{sort} = 'Incoming';
		if ($eproc) {
			$conn->{eproc} = $eproc;
		}
		if ($rproc) {
			$conn->{rproc} = $rproc;
			$conn->{sock}->on_read(sub {$conn->_rcv});
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
	undef $conn->{sock};
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
	return defined $_[0] ? $conn->{disable_read} = $_[0] : $_[0];
}

sub sleep
{
	my ($pkg, $interval) = @_;
	my $cv = AnyEvent->condvar;
	my $wait_a_bit = AnyEvent->timer(
									 after => $interval,
									 cb => sub {$cv->send},
									);
	$cv->recv;
}

sub set_event_handler
{
	my $sock = shift;
	my %args = @_;
	my ($pkg, $fn, $line) = caller;
	my $s;
	foreach (my ($k,$v) = each %args) {
		$s .= "$k => $v, ";
	}
	$s =~ s/[\s,]$//;
	dbg("Msg::set_event_handler called from ${pkg}::${fn} line $line doing $s");
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

