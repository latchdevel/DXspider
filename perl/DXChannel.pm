#
# module to manage channel lists & data
#
# This is the base class for all channel operations, which is everything to do 
# with input and output really.
#
# The instance variable in the outside world will be generally be called $dxchann
#
# This class is 'inherited' (if that is the goobledegook for what I am doing)
# by various other modules. The point to understand is that the 'instance variable'
# is in fact what normal people would call the state vector and all useful info
# about a connection goes in there.
#
# Another point to note is that a vector may contain a list of other vectors. 
# I have simply added another variable to the vector for 'simplicity' (or laziness
# as it is more commonly called)
#
# PLEASE NOTE - I am a C programmer using this as a method of learning perl
# firstly and OO about ninthly (if you don't like the design and you can't 
# improve it with better OO by make it smaller and more efficient, then tough). 
#
# Copyright (c) 1998 - Dirk Koopman G1TLH
#
# $Id$
#
package DXChannel;

use Msg;
use DXM;
use DXUtil;
use DXDebug;
use Carp;

use strict;
use vars qw(%channels %valid);

%channels = undef;

%valid = (
  call => '0,Callsign',
  conn => '9,Msg Conn ref',
  user => '9,DXUser ref',
  startt => '0,Start Time,atime',
  t => '9,Time,atime',
  pc50_t => '9,Last PC50 Time,atime',
  priv => '9,Privilege',
  state => '0,Current State',
  oldstate => '5,Last State',
  list => '9,Dep Chan List',
  name => '0,User Name',
  consort => '9,Connection Type',
  sort => '9,Type of Channel',
  wwv => '0,Want WWV,yesno',
  talk => '0,Want Talk,yesno',
  ann => '0,Want Announce,yesno',
  here => '0,Here?,yesno',
  confmode => '0,In Conference?,yesno',
  dx => '0,DX Spots,yesno',
  redirect => '0,Redirect messages to',
  lang => '0,Language',
  func => '9,Function',
  loc => '9,Local Vars',     # used by func to store local variables in 
);

# create a new channel object [$obj = DXChannel->new($call, $msg_conn_obj, $user_obj)]
sub alloc
{
  my ($pkg, $call, $conn, $user) = @_;
  my $self = {};
  
  die "trying to create a duplicate channel for $call" if $channels{$call};
  $self->{call} = $call;
  $self->{conn} = $conn if defined $conn;   # if this isn't defined then it must be a list
  $self->{user} = $user if defined $user; 
  $self->{startt} = $self->{t} = time;
  $self->{state} = 0;
  $self->{oldstate} = 0;
  bless $self, $pkg; 
  return $channels{$call} = $self;
}

# obtain a channel object by callsign [$obj = DXChannel->get($call)]
sub get
{
  my ($pkg, $call) = @_;
  return $channels{$call};
}

# obtain all the channel objects
sub get_all
{
  my ($pkg) = @_;
  return values(%channels);
}

# obtain a channel object by searching for its connection reference
sub get_by_cnum
{
  my ($pkg, $conn) = @_;
  my $self;
  
  foreach $self (values(%channels)) {
    return $self if ($self->{conn} == $conn);
  }
  return undef;
}

# get rid of a channel object [$obj->del()]
sub del
{
  my $self = shift;
  delete $channels{$self->{call}};
}

# is it an ak1a cluster ?
sub is_ak1a
{
  my $self = shift;
  return $self->{sort} eq 'A';
}

# is it a user?
sub is_user
{
  my $self = shift;
  return $self->{sort} eq 'U';
}

# is it a connect type
sub is_connect
{
  my $self = shift;
  return $self->{sort} eq 'C';
}

# handle out going messages, immediately without waiting for the select to drop
# this could, in theory, block
sub send_now
{
  my $self = shift;
  my $conn = $self->{conn};
  my $sort = shift;
  my $call = $self->{call};
  my $line;
	
  foreach $line (@_) {
    chomp $line;
	dbg('chan', "-> $sort $call $line\n") if $conn;
	$conn->send_now("$sort$call|$line") if $conn;
  }
  $self->{t} = time;
}

#
# the normal output routine
#
sub send              # this is always later and always data
{
  my $self = shift;
  my $conn = $self->{conn};
  my $call = $self->{call};
  my $line;

  foreach $line (@_) {
    chomp $line;
	dbg('chan', "-> D $call $line\n") if $conn;
	$conn->send_later("D$call|$line") if $conn;
  }
  $self->{t} = time;
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
  $self->send(@buf);
}

# this will implement language independence (in time)
sub msg
{
  my $self = shift;
  return DXM::msg(@_);
}

# change the state of the channel - lots of scope for debugging here :-)
sub state
{
  my $self = shift;
  if (@_) {
    $self->{oldstate} = $self->{state};
    $self->{state} = shift;
    dbg('state', "$self->{call} channel func $self->{func} state $self->{oldstate} -> $self->{state}\n");
  }
  return $self->{state};
}

# disconnect this channel
sub disconnect
{
  my $self = shift;
  my $user = $self->{user};
  my $conn = $self->{conn};
  $self->finish();
  $user->close() if defined $user;
  $conn->disconnect() if defined $conn;
  $self->del();
}

# various access routines

#
# return a list of valid elements 
# 

sub fields
{
  return keys(%valid);
}

#
# return a prompt for a field
#

sub field_prompt
{ 
  my ($self, $ele) = @_;
  return $valid{$ele};
}

no strict;
sub AUTOLOAD
{
  my $self = shift;
  my $name = $AUTOLOAD;
  return if $name =~ /::DESTROY$/;
  $name =~ s/.*:://o;
  
  confess "Non-existant field '$AUTOLOAD'" if !$valid{$name};
  @_ ? $self->{$name} = shift : $self->{$name} ;
}

1;
__END__;
