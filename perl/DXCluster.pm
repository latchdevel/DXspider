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
use DXDebug;
use Carp;

use strict;
use vars qw(%cluster %valid);

%cluster = ();					# this is where we store the dxcluster database

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

# get an entry exactly as it is
sub get_exact
{
	my ($pkg, $call) = @_;

	# belt and braces
	$call = uc $call;
  
	# search for 'as is' only
	return $cluster{$call}; 
}

#
# search for a call in the cluster
# taking into account SSIDs
#
sub get
{
	my ($pkg, $call) = @_;

	# belt and braces
	$call = uc $call;
  
	# search for 'as is'
	my $ref = $cluster{$call}; 
	return $ref if $ref;

	# search for the unSSIDed one
	$call =~ s/-\d+$//o;
	$ref = $cluster{$call};
	return $ref if $ref;
  
	# search for the SSIDed one
	my $i;
	for ($i = 1; $i < 17; $i++) {
		$ref = $cluster{"$call-$i"};
		return $ref if $ref;
	}
	return undef;
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

# the answer required by show/cluster
sub cluster
{
	my $users = DXCommandmode::get_all();
	my $uptime = main::uptime();
	my $tot = $DXNode::users + 1;
		
	return " $DXNode::nodes nodes, $users local / $tot total users  Max users $DXNode::maxusers  Uptime $uptime";
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

sub new 
{
	my ($pkg, $dxchan, $node, $call, $confmode, $here) = @_;

	die "tried to add $call when it already exists" if DXCluster->get_exact($call);
  
	my $self = $pkg->alloc($dxchan, $call, $confmode, $here);
	$self->{mynode} = $node;
	$node->{list}->{$call} = $self;	# add this user to the list on this node
	dbg('cluster', "allocating user $call to $node->{call} in cluster\n");
	$node->update_users();
	return $self;
}

sub del
{
	my $self = shift;
	my $call = $self->{call};
	my $node = $self->{mynode};

	delete $node->{list}->{$call};
	delete $DXCluster::cluster{$call}; # remove me from the cluster table
	dbg('cluster', "deleting user $call from $node->{call} in cluster\n");
	$node->update_users();
}

sub count
{
	return $DXNode::users;		# + 1 for ME (naf eh!)
}

no strict;

#
# NODE special routines
#

package DXNode;

@ISA = qw(DXCluster);

use DXDebug;

use strict;
use vars qw($nodes $users $maxusers);

$nodes = 0;
$users = 0;
$maxusers = 0;


sub new 
{
	my ($pkg, $dxchan, $call, $confmode, $here, $pcversion) = @_;
	my $self = $pkg->alloc($dxchan, $call, $confmode, $here);
	$self->{pcversion} = $pcversion;
	$self->{list} = { } ;
	$self->{mynode} = $self;	# for sh/station
	$self->{users} = 0;
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
		$ref->del();			# this also takes them out of this list
	}
	delete $DXCluster::cluster{$call}; # remove me from the cluster table
	dbg('cluster', "deleting node $call from cluster\n"); 
	$nodes-- if $nodes > 0;
}

sub update_users
{
	my $self = shift;
	my $count = shift;
	$count = 0 unless $count;
  
	$users -= $self->{users} if $self->{users};
	if ((keys %{$self->{list}})) {
		$self->{users} = (keys %{$self->{list}});
	} else {
		$self->{users} = $count;
	}
	$users += $self->{users} if $self->{users};
	$maxusers = $users+$nodes if $users+$nodes > $maxusers;
}

sub count
{
	return $nodes;				# + 1 for ME!
}

sub dolist
{

}
1;
__END__
