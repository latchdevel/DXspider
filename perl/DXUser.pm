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
use Carp;

use strict;
use vars qw(%u $dbm $filename %valid);

%u = ();
$dbm = undef;
$filename = undef;

# hash of valid elements and a simple prompt
%valid = (
  call => '0,Callsign',
  alias => '0,Real Callsign',
  name => '0,Name',
  qth => '0,Home QTH',
  lat => '0,Latitude,slat',
  long => '0,Longitude,slong',
  qra => '0,Locator',
  email => '0,E-mail Address',
  priv => '9,Privilege Level',
  lastin => '0,Last Time in,cldatetime',
  passwd => '9,Password',
  addr => '0,Full Address',
  'sort' => '0,Type of User',                # A - ak1a, U - User, S - spider cluster, B - BBS
  xpert => '0,Expert Status,yesno',
  bbs => '0,Home BBS',
  node => '0,Last Node',
  homenode => '0,Home Node',
  lockout => '9,Locked out?,yesno',        # won't let them in at all
  dxok => '9,DX Spots?,yesno',            # accept his dx spots?
  annok => '9,Announces?,yesno',            # accept his announces?
  reg => '0,Registered?,yesno',            # is this user registered?
  lang => '0,Language',
  hmsgno => '0,Highest Msgno',
  group => '0,Access Group,parray',               # used to create a group of users/nodes for some purpose or other
  isolate => '9,Isolate network,yesno',
);

no strict;
sub AUTOLOAD
{
  my $self = shift;
  my $name = $AUTOLOAD;
  
  return if $name =~ /::DESTROY$/;
  $name =~ s/.*:://o;
  
  confess "Non-existant field '$AUTOLOAD'" if !$valid{$name};
  if (@_) {
    $self->{$name} = shift;
	$self->put();
  }
  return $self->{$name};
}

#
# initialise the system
#
sub init
{
  my ($pkg, $fn) = @_;
  
  confess "need a filename in User" if !$fn;
  $dbm = tie (%u, MLDBM, $fn, O_CREAT|O_RDWR, 0666) or confess "can't open user file: $fn ($!)";
  $filename = $fn;
}

use strict;

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
  my $pkg = shift;
  my $call = uc shift;
#  $call =~ s/-\d+$//o;
  
  confess "can't create existing call $call in User\n!" if $u{$call};

  my $self = {};
  $self->{call} = $call;
  $self->{'sort'} = 'U';
  $self->{dxok} = 1;
  $self->{annok} = 1;
  $self->{lang} = $main::lang;
  bless $self, $pkg;
  $u{call} = $self;
}

#
# get - get an existing user - this seems to return a different reference everytime it is
#       called - see below
#

sub get
{
  my $pkg = shift;
  my $call = uc shift;
#  $call =~ s/-\d+$//o;       # strip ssid
  return $u{$call};
}

#
# get all callsigns in the database 
#

sub get_all_calls
{
  return (sort keys %u);
}

#
# get an existing either from the channel (if there is one) or from the database
#
# It is important to note that if you have done a get (for the channel say) and you
# want access or modify that you must use this call (and you must NOT use get's all
# over the place willy nilly!)
#

sub get_current
{
  my $pkg = shift;
  my $call = uc shift;
#  $call =~ s/-\d+$//o;       # strip ssid
  
  my $dxchan = DXChannel->get($call);
  return $dxchan->user if $dxchan;
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

sub fields
{
  return keys(%valid);
}

#
# group handling
#

# add one or more groups
sub add_group
{
	my $self = shift;
	my $ref = $self->{group} || [ 'local' ];
	$self->{group} = $ref if !$self->{group};
	push @$ref, @_ if @_;
}

# remove one or more groups
sub del_group
{
	my $self = shift;
	my $ref = $self->{group} || [ 'local' ];
	my @in = @_;
	
	$self->{group} = $ref if !$self->{group};
	
	@$ref = map { my $a = $_; return (grep { $_ eq $a } @in) ? () : $a } @$ref;
}

# does this thing contain all the groups listed?
sub union
{
	my $self = shift;
	my $ref = $self->{group};
	my $n;
	
	return 0 if !$ref || @_ == 0;
	return 1 if @$ref == 0 && @_ == 0;
	for ($n = 0; $n < @_; ) {
		for (@$ref) {
			my $a = $_;
			$n++ if grep $_ eq $a, @_; 
		}
	}
	return $n >= @_;
}

# simplified group test just for one group
sub in_group
{
	my $self = shift;
	my $s = shift;
	my $ref = $self->{group};
	
	return 0 if !$ref;
	return grep $_ eq $s, $ref;
}

# set up a default group (only happens for them's that connect direct)
sub new_group
{
	my $self = shift;
	$self->{group} = [ 'local' ];
}

#
# return a prompt for a field
#

sub field_prompt
{ 
  my ($self, $ele) = @_;
  return $valid{$ele};
}

# some variable accessors
sub sort
{
  my $self = shift;
  @_ ? $self->{'sort'} = shift : $self->{'sort'} ;
}
1;
__END__
