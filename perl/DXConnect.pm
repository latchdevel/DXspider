#
# module to manage connection lists & data
#

package DXConnect;

require Exporter;
@ISA = qw(Exporter);

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

1;
__END__;
