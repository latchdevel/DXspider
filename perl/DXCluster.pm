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

%cluster = ();            # this is where we store the dxcluster database

sub alloc
{
  my ($pkg, $call, $confmode, $here, $dxprot) = @_;
  die "$call is already alloced" if $cluster{$call};
  my $self = {};
  $self->{call} = $call;
  $self->{confmode} = $confmode;
  $self->{here} = $here;
  $self->{dxprot} = $dxprot;

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

%valid = (
  mynode => 'Parent Node',
  call => 'Callsign',
  confmode => 'Conference Mode',
  here => 'Here?',
  dxprot => 'Channel ref',
  version => 'Node Version',
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
# USER special routines
#

package DXUser;

@ISA = qw(DXCluster);

%users = ();

sub new 
{
  my ($pkg, $mynode, $call, $confmode, $here, $dxprot) = @_;
  my $self = $pkg->alloc($call, $confmode, $here, $dxprot);
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

#
# NODE special routines
#

package DXNode;

@ISA = qw(DXCluster);

%nodes = ();

sub new 
{
  my ($pkg, $call, $confmode, $here, $version, $dxprot) = @_;
  my $self = $pkg->alloc($call, $confmode, $here, $dxprot);
  $self->{version} = $version;
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
    push @out, $list if $list->{version};
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
