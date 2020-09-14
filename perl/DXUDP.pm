package DXUDP;

=head1 NAME

DXUDP - A Mojo compatible UDP thingy

=head1 VERSION

0.01

=head1 SYNOPSIS

    use DXUDP;
    my $handle = DXUDP->new;

    $handle->on(read => sub {
        my ($handle, $data) = @_;
        ...
    });

    $handle->on(error => sub {
        warn "DXUDP: $_[1]\n";
    });

    $handle->on(finish => sub {
        my($handle, $c, $error) = @_;
        warn "Connection: $error\n" if $error;
    });

    $handle->start;
    $handle->ioloop->start unless $handle->ioloop->is_running;

=head1 DESCRIPTION

A simple Mojo compatible UDP thingy

=cut

use Mojo::Base 'Mojo::EventEmitter';
use Mojo::IOLoop;
use Scalar::Util qw(weaken);
use IO::Socket::INET6;

our $VERSION = '0.04';

=head1 EVENTS

=head2 error

    $self->on(error => sub {
        my($self, $str) = @_;
    });

This event is emitted when something goes wrong: Fail to L</listen> to socket,
read from socket or other internal errors.

=head2 finish

    $self->on(finish => sub {
        my($self, $c, $error) = @_;
    });

This event is emitted when the client finish, either successfully or due to an
error. C<$error> will be an empty string on success.

=head2 read

    $self->on(read => sub {
        my($self, $data) = @_;
    });

This event is emitted when a new read request arrives from a client.

=head1 ATTRIBUTES

=head2 ioloop

Holds an instance of L<Mojo::IOLoop>.

=cut

has ioloop => sub { Mojo::IOLoop->singleton };

=head2 inactive_timeout

How long a L<connection|Mojo::TFTPd::Connection> can stay idle before
being dropped. Default is 0 (no timeout).

=cut

has inactive_timeout => 0;


=head1 METHODS

=head2 start

Starts listening to the address and port set in L</Listen>. The L</error>
event will be emitted if the server fail to start.

=cut

sub start {
    my ($self, $args) = (shift, ref $_[0] ? $_[0] : {@_});
    my $reactor = $self->ioloop->reactor;
    my $socket;

	my $host = $args->{LocalAddr} || $args->{host} || '0.0.0.0';
	my $port = $args->{LocalPort} || $args->{port} || 1234;
	
    $socket = IO::Socket::INET6->new(
                  LocalAddr => $host,
                  LocalPort => $port,
                  Proto => 'udp',
              );

    if(!$socket) {
        return $self->emit(error => "Can't create listen socket: $!");
    };

    Scalar::Util::weaken($self);

    $socket->blocking(0);
    $reactor->io($socket, sub { $self->_incoming });
    $reactor->watch($socket, 1, 0); # watch read events
    $self->{socket} = $socket;

    return $self;
}

sub _incoming {
    my $self = shift;
    my $socket = $self->{socket};
    my $read = $socket->recv(my $datagram, 65534); 

    if(!defined $read) {
        $self->emit(error => "Read: $!");
    }

	$self->emit(read => $datagram);
}	


sub DEMOLISH {
    my $self = shift;
    my $reactor = eval { $self->ioloop->reactor } or return; # may be undef during global destruction

    $reactor->remove($self->{socket}) if $self->{socket};
}

=head1 AUTHOR

Svetoslav Naydenov - C<harryl@cpan.org>

Jan Henning Thorsen - C<jhthorsen@cpan.org>

=cut

1;
