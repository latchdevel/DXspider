#
# DX database control routines
#
# This manages the on-line cluster user 'database'
#
# This should all be pretty trees and things, but for now I
# just can't be bothered. If it becomes an issue I shall
# address it.
#
# Copyright (c) 1998 - Dirk Koopman G1TLH
#
# $Id$
#

package DXCluster;

use Exporter;
@ISA = qw(Exporter);

use strict;

my %cluster = ();            # this is where we store the dxcluster database

my %valid = (
  mynode => '0,Parent Node',
  call => '0,Callsign',
  confmode => '0,Conference Mode,yesno',
  here => '0,Here?,yesno',
  dxchan => '5,Channel ref',
  pcversion => '5,Node Version',
);

sub alloc
{
  my ($pkg, $call, $confmode, $here, $dxchan) = @_;
  die "$call is already alloced" if $cluster{$call};
  my $self = {};
  $self->{call} = $call;
  $self->{confmode} = $confmode;
  $self->{here} = $here;
  $self->{dxchan} = $dxchan;

  $cluster{$call} = bless $self, $pkg;
  return $self;
}

# search for a call in the cluster
sub get
{
  my ($pkg, $call) = @_;
  return $cluster{$call};
}

# get all 
sub get_all
{
  return values(%cluster);
}

sub delcluster;
{
  my $self = shift;
  delete $cluster{$self->{call}};
}


# return a prompt for a field
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
  
  die "Non-existant field '$AUTOLOAD'" if !$valid{$name};
  @_ ? $self->{$name} = shift : $self->{$name} ;
}

#
# USER special routines
#

package DXNodeuser;

@ISA = qw(DXCluster);

use strict;
my %users = ();

sub new 
{
  my ($pkg, $mynode, $call, $confmode, $here, $dxchan) = @_;
  my $self = $pkg->alloc($call, $confmode, $here, $dxchan);
  $self->{mynode} = $mynode;

  $users{$call} = $self;
  return $self;
}

sub delete
{
  my $self = shift;
  $self->delcluster();              # out of the whole cluster table
  delete $users{$self->{call}};     # out of the users table
}

sub count
{
  return %users + 1;                 # + 1 for ME (naf eh!)
}

no strict;

#
# NODE special routines
#

package DXNode;

@ISA = qw(DXCluster);

use strict;
my %nodes = ();

sub new 
{
  my ($pkg, $call, $confmode, $here, $pcversion, $dxchan) = @_;
  my $self = $pkg->alloc($call, $confmode, $here, $dxchan);
  $self->{version} = $pcversion;
  $nodes{$call} = $self;
  return $self;
}

# get a node
sub get
{
  my ($pkg, $call) = @_;
  return $nodes{$call};
}

# get all the nodes
sub get_all
{
  my $list;
  my @out;
  foreach $list (values(%nodes)) {
    push @out, $list if $list->{pcversion};
  }
  return @out;
}

sub delete
{
  my $self = shift;
  my $call = $self->call;
  
  DXUser->delete($call);     # delete all the users one this node
  delete $nodes{$call};
}

sub count
{
  return %nodes + 1;           # + 1 for ME!
}
1;
__END__
