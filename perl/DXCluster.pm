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
use Carp;
use DXDebug;

use strict;
use vars qw(%cluster %valid);

%cluster = ();            # this is where we store the dxcluster database

%valid = (
  mynode => '0,Parent Node,showcall',
  call => '0,Callsign',
  confmode => '0,Conference Mode,yesno',
  here => '0,Here?,yesno',
  dxchan => '5,Channel ref',
  pcversion => '5,Node Version',
  list => '5,User List,dolist',
  users => '0,No of Users',
);

sub alloc
{
  my ($pkg, $dxchan, $call, $confmode, $here) = @_;
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

# return a prompt for a field
sub field_prompt
{ 
  my ($self, $ele) = @_;
  return $valid{$ele};
}

# this expects a reference to a list in a node NOT a ref to a node 
sub dolist
{
  my $self = shift;
  my $out;
  my $ref;
  
  foreach $ref (@{$self}) {
    my $s = $ref->{call};
	$s = "($s)" if !$ref->{here};
	$out .= "$s ";
  }
  chop $out;
  return $out;
}

# this expects a reference to a node 
sub showcall
{
  my $self = shift;
  return $self->{call};
}

sub DESTROY
{
  my $self = shift;
  dbg('cluster', "destroying $self->{call}\n");
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

#
# USER special routines
#

package DXNodeuser;

@ISA = qw(DXCluster);

use DXDebug;

use strict;
my $users = 0;

sub new 
{
  my ($pkg, $dxchan, $node, $call, $confmode, $here) = @_;

  die "tried to add $call when it already exists" if DXCluster->get($call);
  
  my $self = $pkg->alloc($dxchan, $call, $confmode, $here);
  $self->{mynode} = $node;
  $node->{list}->{$call} = $self;     # add this user to the list on this node
  $users++;
  dbg('cluster', "allocating user $call to $node->{call} in cluster\n");
  return $self;
}

sub del
{
  my $self = shift;
  my $call = $self->{call};
  my $node = $self->{mynode};
 
  delete $node->{list}->{$call};
  delete $DXCluster::cluster{$call};     # remove me from the cluster table
  dbg('cluster', "deleting user $call from $node->{call} in cluster\n");
  $users-- if $users > 0;
}

sub count
{
  return $users;                 # + 1 for ME (naf eh!)
}

no strict;

#
# NODE special routines
#

package DXNode;

@ISA = qw(DXCluster);

use DXDebug;

use strict;
my $nodes = 0;

sub new 
{
  my ($pkg, $dxchan, $call, $confmode, $here, $pcversion) = @_;
  my $self = $pkg->alloc($dxchan, $call, $confmode, $here);
  $self->{version} = $pcversion;
  $self->{list} = { } ;
  $nodes++;
  dbg('cluster', "allocating node $call to cluster\n");
  return $self;
}

# get all the nodes
sub get_all
{
  my $list;
  my @out;
  foreach $list (values(%DXCluster::cluster)) {
    push @out, $list if $list->{pcversion};
  }
  return @out;
}

sub del
{
  my $self = shift;
  my $call = $self->{call};
  my $ref;

  # delete all the listed calls
  foreach $ref (values %{$self->{list}}) {
    $ref->del();      # this also takes them out of this list
  }
  dbg('cluster', "deleting node $call from cluster\n"); 
  $nodes-- if $nodes > 0;
}

sub update_users
{
  my $self = shift;
  if (%{$self->{list}}) {
    $self->{users} = scalar %{$self->{list}};
  } else {
    $self->{users} = shift;
  }
}

sub count
{
  return $nodes;           # + 1 for ME!
}

sub dolist
{

}
1;
__END__
