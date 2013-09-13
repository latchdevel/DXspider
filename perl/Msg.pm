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

use Mojo::IOLoop;
use Mojo::IOLoop::Stream;

use DXDebug;
use Timer;

use vars qw($now %conns $noconns $cnum $total_in $total_out);

$total_in = $total_out = 0;

$now = time;

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
	
	dbg("$class Connection created (total $noconns)") if isdbg('connll');
	return bless $conn, $class;
}

sub set_error
{
	my $conn = shift;
	my $callback = shift;
	$conn->{sock}->on(error => sub {my ($stream, $err) = @_; $callback->($conn, $err);});
}

sub set_on_eof
{
	my $conn = shift;
	my $callback = shift;
	$conn->{sock}->on(close => sub {$callback->($conn);});
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
		dbg((ref $pkg) . " changing $pkg->{call} to $call") if isdbg('connll') && exists $pkg->{call} && $call ne $pkg->{call};
		delete $conns{$pkg->{call}} if exists $pkg->{call} && exists $conns{$pkg->{call}} && $pkg->{call} ne $call; 
		$pkg->{call} = $call;
		$ref = $conns{$call} = $pkg;
		dbg((ref $pkg) . " Connection $pkg->{cnum} $call stored") if isdbg('connll');
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
	$conn->{peerhost} ||= $conn->{sock}->handle->peerhost if $conn->{sock};
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

	dbg((ref $conn) . " connecting $conn->{cnum} to $to_host:$to_port") if isdbg('connll');
	
	my $sock;
	$conn->{sock} = $sock = Mojo::IOLoop::Client->new;
	$sock->on(connect => sub { dbg((ref $conn) . " connected $conn->{cnum} to $to_host:$to_port") if isdbg('connll');}, 
			  error => {$conn->disconnect},
			  close => {$conn->disconnect});
	
	$sock->connect(address => $to_host, port => $to_port);
	
	dbg((ref $conn) . " connected $conn->{cnum} to $to_host:$to_port") if isdbg('connll');

    if ($conn->{rproc}) {
		$sock->on(read => sub {my ($stream, $msg) = @_; $conn->_rcv($msg);} );
    }
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
	dbg((ref $conn) . " Connection $conn->{cnum} $call disconnected") if isdbg('connll');
	
	# get rid of any references
	for (keys %$conn) {
		if (ref($conn->{$_})) {
			delete $conn->{$_};
		}
	}

	if (defined($sock)) {
		$sock->remove;
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
			$sock->write($data);
			$total_out = $lth;
		} else {
			dbg("_send_stuff $call ending data ignored: $data");
		}
	}
}

sub send_now {
    my ($conn, $msg) = @_;
    $conn->enqueue($msg);
    _send_stuff($conn);
}

sub send_later {
	goto &send_now;
}

sub enqueue {
    my $conn = shift;
    push @{$conn->{outqueue}}, defined $_[0] ? $_[0] : '';
}

sub _err_will_block 
{
	return 0;
}

sub close_on_empty
{
	my $conn = shift;
	$conn->{sock}->on(drain => sub {$conn->disconnect;});
}

#-----------------------------------------------------------------
# Receive side routines

sub new_server 
{
#    @_ == 4 || die "Msg->new_server (myhost, myport, login_proc)\n";
	my ($pkg, $my_host, $my_port, $login_proc) = @_;
	my $conn = $pkg->new($login_proc);
	
    $conn->{sock} = Mojo::IOLoop::Server->new;
	$conn->{sock}->on(accept=>sub{$conn->new_client()});
	$conn->{sock}->listen(address=>$my_host, port=>$my_port);
	
    die "Could not create socket: $! \n" unless $conn->{sock};
	return $conn;
}


sub nolinger
{
	my $conn = shift;
}

sub dequeue
{
	my $conn = shift;
	return if $conn->{disconnecting};
	
	if ($conn->{msg} =~ /\cJ/) {
		my @lines = split /\cM?\cJ/, $conn->{msg};
		if ($conn->{msg} =~ /\cM?\cJ$/) {
			delete $conn->{msg};
		} else {
			$conn->{msg} = pop @lines;
		}
		for (@lines) {
			last if $conn->{disconnecting};
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
#	if ($conn->{blocking}) {
#		blocking($sock, 0);
#		$conn->{blocking} = 0;
#	}
	$bytes_read = sysread ($sock, $msg, 1024, 0);
	if (defined ($bytes_read)) {
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
	my $client = shift;
	
	my $conn = $server_conn->new($server_conn->{rproc});
	my $sock = $conn->{sock} = Mojo::IOLoop::Stream->new($client);
	$sock->on(read => sub {$conn->_rcv($_[1])});
	dbg((ref $conn) . "accept $conn->{cnum} from $conn->{peerhost} $conn->{peerport}") if isdbg('connll');

	my ($rproc, $eproc) = &{$server_conn->{rproc}} ($conn, $conn->{peerhost} = $client->peerhost, $conn->{peerport} = $client->peerport);
	$conn->{sort} = 'Incoming';
	if ($eproc) {
		$conn->{eproc} = $eproc;
	}
	if ($rproc) {
		$conn->{rproc} = $rproc;
	} else {  # Login failed
		&{$conn->{eproc}}($conn, undef) if exists $conn->{eproc};
		$conn->disconnect();
	}
}

sub close_server
{
	my $conn = shift;
	delete $conn->{sock};
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


#
#----------------------------------------------------
# Event loop routines used by both client and server

sub set_event_handler {
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

sub sleep
{
	my ($pkg, $interval) = @_;
	my $now = time;
	while (time - $now < $interval) {
		sleep 1;
	}
}

sub DESTROY
{
	my $conn = shift;
	my $call = $conn->{call} || 'unallocated';
	my $host = $conn->{peerhost} || '';
	my $port = $conn->{peerport} || '';
	$noconns--;
	dbg((ref $conn) . " Connection $conn->{cnum} $call [$host $port] being destroyed (total $noconns)") if isdbg('connll');
}

1;

__END__

