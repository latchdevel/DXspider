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

require Exporter;
@ISA = qw(DXCommandmode DXProt Exporter);

use Msg;
use DXUtil;
use DXM;

%channels = undef;

# create a new connection object [$obj = DXChannel->new($call, $msg_conn_obj, $user_obj)]
sub new
{
  my ($pkg, $call, $conn, $user) = @_;
  my $self = {};
  
  die "trying to create a duplicate channel for $call" if $channels{$call};
  $self->{call} = $call;
  $self->{conn} = $conn if defined $conn;   # if this isn't defined then it must be a list
  $self->{user} = $user if defined $user; 
  $self->{t} = time;
  $self->{state} = 0;
  bless $self, $pkg; 
  return $channels{$call} = $self;
}

# obtain a connection object by callsign [$obj = DXChannel->get($call)]
sub get
{
  my ($pkg, $call) = @_;
  return $connect{$call};
}

# obtain all the connection objects
sub get_all
{
  my ($pkg) = @_;
  return values(%channels);
}

# obtain a connection object by searching for its connection reference
sub get_by_cnum
{
  my ($pkg, $conn) = @_;
  my $self;
  
  foreach $self (values(%channels)) {
    return $self if ($self->{conn} == $conn);
  }
  return undef;
}

# get rid of a connection object [$obj->del()]
sub del
{
  my $self = shift;
  delete $channels{$self->{call}};
}


# handle out going messages, immediately without waiting for the select to drop
# this could, in theory, block
sub send_now
{
  my $self = shift;
  my $conn = $self->{conn};

  # is this a list of channels ?
  if (!defined $conn) {
    die "tried to send_now to an invalid channel list" if !defined $self->{list};
	my $lself;
	foreach $lself (@$self->{list}) {
	  $lself->send_now(@_);             # it's recursive :-)
	}
  } else {
    my $sort = shift;
    my $call = $self->{call};
    my $line;
	
    foreach $line (@_) {
      my $t = atime;
	  chomp $line;
      print main::DEBUG "$t > $sort $call $line\n" if defined DEBUG;
	  print "> $sort $call $line\n";
      $conn->send_now("$sort$call|$line");
	}
  }
}

#
# the normal output routine
#
sub send              # this is always later and always data
{
  my $self = shift;
  my $conn = $self->{conn};
 
  # is this a list of channels ?
  if (!defined $conn) {
    die "tried to send to an invalid channel list" if !defined $self->{list};
	my $lself;
	foreach $lself (@$self->{list}) {
	  $lself->send(@_);                 # here as well :-) :-)
	}
  } else {
    my $call = $self->{call};
    my $line;

    foreach $line (@_) {
      my $t = atime;
	  chomp $line;
	  print main::DEBUG "$t > D $call $line\n" if defined DEBUG;
	  print "> D $call $line\n";
	  $conn->send_later("D$call|$line");
	}
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
  $self->send(@buf);
}

# just a shortcut for $dxchan->send(msg(...));
sub msg
{
  my $self = shift;
  $self->send(DXM::msg(@_));
}

1;
__END__;
