#
# DX cluster user routines
#
# Copyright (c) 1998 - Dirk Koopman G1TLH
#
# $Id$
#

package DXUser;

require Exporter;
@ISA = qw(Exporter);

use MLDBM;
use Fcntl;

%u = undef;
$dbm = undef;
$filename = undef;

#
# initialise the system
#
sub init
{
  my ($pkg, $fn) = @_;
  
  die "need a filename in User\n" if !$fn;
  $dbm = tie %u, MLDBM, $fn, O_CREAT|O_RDWR, 0666 or die "can't open user file: $fn ($!)\n";
  $filename = $fn;
}

#
# close the system
#

sub finish
{
  $dbm = undef;
  untie %u;
}

#
# new - create a new user
#

sub new
{
  my ($call) = @_;
  die "can't create existing call $call in User\n!" if $u{$call};

  my $self = {};
  $self->{call} = $call;
  bless $self;
  $u{call} = $self;
}

#
# get - get an existing user
#

sub get
{
  my ($call) = @_;
  return $u{$call};
}

#
# put - put a user
#

sub put
{
  my $self = shift;
  my $call = $self->{call};
  $u{$call} = $self;
}

#
# del - delete a user
#

sub del
{
  my $self = shift;
  my $call = $self->{call};
  delete $u{$call};
}

#
# close - close down a user
#

sub close
{
  my $self = shift;
  $self->{lastin} = time;
  $self->put();
}

1;
__END__
