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

use MLDBM qw(DB_File);
use Fcntl;

%u = undef;
$dbm = undef;
$filename = undef;

# hash of valid elements and a simple prompt
%valid = (
  call => 'Callsign',
  alias => 'Real Callsign',
  name => 'Name',
  qth => 'Home QTH',
  lat => 'Latitude',
  long => 'Longtitude',
  qra => 'Locator',
  email => 'E-mail Address',
  priv => 'Privilege Level',
  lastin => 'Last Time in',
  passwd => 'Password',
  addr => 'Full Address',
  'sort' => 'Type of User',  # A - ak1a, U - User, S - spider cluster, B - BBS 
);

sub AUTOLOAD
{
  my $self = shift;
  my $name = $AUTOLOAD;
  
  return if $name =~ /::DESTROY$/;
  $name =~ s/.*:://o;
  
  die "Non-existant field '$AUTOLOAD'" if !$valid{$name};
  @_ ? $self->{$name} = shift : $self->{$name} ;
}

#
# initialise the system
#
sub init
{
  my ($pkg, $fn) = @_;
  
  die "need a filename in User" if !$fn;
  $dbm = tie %u, MLDBM, $fn, O_CREAT|O_RDWR, 0666 or die "can't open user file: $fn ($!)";
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
  my ($pkg, $call) = @_;
  die "can't create existing call $call in User\n!" if $u{$call};

  my $self = {};
  $self->{call} = $call;
  bless $self, $pkg;
  $u{call} = $self;
}

#
# get - get an existing user
#

sub get
{
  my ($pkg, $call) = @_;
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

#
# return a list of valid elements 
# 

sub elements
{
  return keys(%valid);
}

#
# return a prompt for a field
#

sub prompt
{ 
  my ($self, $ele) = @_;
  return $valid{$ele};
}

#
# enter an element from input, returns 1 for success
#

sub enter
{
  my ($self, $ele, $value) = @_;
  return 0 if (!defined $valid{$ele});
  chomp $value;
  return 0 if $value eq "";
  if ($ele eq 'long') {
    my ($longd, $longm, $longl) = $value =~ /(\d+) (\d+) ([EWew])/;
	return 0 if (!$longl || $longd < 0 || $longd > 180 || $longm < 0 || $longm > 59);
	$longd += ($longm/60);
	$longd = 0-$longd if (uc $longl) eq 'W'; 
	$self->{'long'} = $longd;
	return 1;
  } elsif ($ele eq 'lat') {
    my ($latd, $latm, $latl) = $value =~ /(\d+) (\d+) ([NSns])/;
	return 0 if (!$latl || $latd < 0 || $latd > 90 || $latm < 0 || $latm > 59);
	$latd += ($latm/60);
	$latd = 0-$latd if (uc $latl) eq 'S';
	$self->{'lat'} = $latd;
	return 1;
  } elsif ($ele eq 'qra') {
    $self->{'qra'} = UC $value;
	return 1;
  } else {
    $self->{$ele} = $value;               # default action
	return 1;
  }
  return 0;
}

# some variable accessors
sub sort
{
  my $self = shift;
  @_ ? $self->{sort} = shift : $self->{sort} ;
}
1;
__END__
