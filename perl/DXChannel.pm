#
# module to manage channel lists & data
#
# Copyright (c) 1998 - Dirk Koopman G1TLH
#
# $Id$
#
package DXChannel;

require Exporter;
@ISA = qw(Exporter);

use Msg;

%connects = undef;

# create a new connection object [$obj = Connect->new($call, $msg_conn_obj, $user_obj)]
sub new
{
  my ($pkg, $call, $conn, $user) = @_;
  my $self = {};
  
  die "trying to create a duplicate Connect for call $call\n" if $connects{$call};
  $self->{call} = $call;
  $self->{conn} = $conn;
  $self->{user} = $user;
  $self->{t} = time;
  $self->{state} = 0;
  bless $self, $pkg; 
  return $connects{$call} = $self;
}

# obtain a connection object by callsign [$obj = Connect->get($call)]
sub get
{
  my ($pkg, $call) = @_;
  return $connect{$call};
}

# obtain all the connection objects
sub get_all
{
  my ($pkg) = @_;
  return values(%connects);
}

# obtain a connection object by searching for its connection reference
sub get_by_cnum
{
  my ($pkg, $conn) = @_;
  my $self;
  
  foreach $self (values(%connects)) {
    return $self if ($self->{conn} == $conn);
  }
  return undef;
}

# get rid of a connection object [$obj->del()]
sub del
{
  my $self = shift;
  delete $connects{$self->{call}};
}


# handle out going messages
sub send_now
{
  my $self = shift;
  my $sort = shift;
  my $call = $self->{call};
  my $conn = $self->{conn};
  my $line;

  foreach $line (@_) {
    print DEBUG "$t > $sort $call $line\n" if defined DEBUG;
	print "> $sort $call $line\n";
    $conn->send_now("$sort$call|$line");
  }
}

sub send_later
{
  my $self = shift;
  my $sort = shift;
  my $call = $self->{call};
  my $conn = $self->{conn};
  my $line;

  foreach $line (@_) {
    print DEBUG "$t > $sort $call $line\n" if defined DEBUG;
    print "> $sort $call $line\n";
    $conn->send_later("$sort$call|$line");
  }
}

# send a file (always later)
sub send_file
{
  my ($self, $fn) = @_;
  my $call = $self->{call};
  my $conn = $self->{conn};
  my @buf;
  
  open(F, $fn) or die "can't open $fn for sending file ($!)";
  @buf = <F>;
  close(F);
  $self->send_later('D', @buf);
}

1;
__END__;
