#
# Node routing routines
#
# Copyright (c) 2001 Dirk Koopman G1TLH
#
# $Id$
# 

package Route::Node;

use DXDebug;
use Route;
use Route::User;

use strict;

use vars qw($VERSION $BRANCH);
$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /\d+\.\d+\.(\d+)\.(\d+)/  || (0,0));
$main::build += $VERSION;
$main::branch += $BRANCH;

use vars qw(%list %valid @ISA $max $filterdef);
@ISA = qw(Route);

%valid = (
		  dxchan => '0,DXChannel List,parray',
		  nodes => '0,Nodes,parray',
		  users => '0,Users,parray',
		  usercount => '0,User Count',
		  version => '0,Version',
		  newroute => '0,New Routing?,yesno',
);

$filterdef = $Route::filterdef;
%list = ();
$max = 0;

sub count
{
	my $n = scalar (keys %list);
	$max = $n if $n > $max;
	return $n;
}

sub max
{
	count();
	return $max;
}

# link a node to this node and mark the route as available thru 
# this dxchan, any users must be linked separately
#
# call as $node->link_node($neighbour, $dxchan);
#

sub link_node
{
	my ($self, $neighbour, $dxchan) = @_;

	my $r = $neighbour->is_empty('dxchan');
	$self->_addlist('nodes', $neighbour);
	$neighbour->_addlist('nodes', $self);
	$neighbour->_addlist('dxchan', $dxchan);
	return $r ? ($neighbour) : ();
}

# unlink a node from a neighbour and remove any
# routes, if this node becomes orphaned (no routes
# and no nodes) then return it 
#

sub unlink_node
{
	my ($self, $neighbour, $dxchan) = @_;
	$self->_dellist('nodes', $neighbour);
	$neighbour->_dellist('nodes', $self);
	$neighbour->_dellist('dxchan', $dxchan) if $dxchan;
	return $neighbour->is_empty('dxchan') ? ($neighbour) : ();
}

sub remove_route
{
	my ($self, $neighbour, $dxchan) = @_;

	# cut the dxchan link
	# cut the node link
	my @rout;
	push @rout, $self->unlink_node($neighbour, $dxchan);
	dbg("Orphanning $neighbour->{call}") if isdbg('routelow');
	
	# then run down the tree removing this dxchan link from
	# all the referenced nodes that use this interface
	my %visited;
	my @in = map { Route::Node::get($_) } $neighbour->nodes;
	foreach my $r (@in) {
		next unless $r;
		next if $visited{$r->call};
		my ($o) = $r->del_dxchan($self);
		if ($o) {
			dbg("Orphanning $_->{call}") if isdbg('routelow');
			push @rout, $o;
		}
		push @in, map{ Route::Node::get($_) } $r->nodes;
		$visited{$r->call} = $r;
	}
	
	# in @rout there should be a list of orphaned (in dxchan terms)
	# nodes. Now go thru and make sure that all their links are
	# broken (they should be, but this is to check).
	
	foreach my $r (@rout) {
		my @nodes = map { Route::Node::get($_)} $r->nodes;
		for (@nodes) {
			next unless $_;
			dbg("Orphaned node $_->{call}: breaking link to $_->{call}") if isdbg('routelow');
			$r->unlink_node($_);
		}
	}
	return @rout;
}

# add a user to this node
# returns Route::User if it is a new user;
sub add_user
{
	my ($self, $uref) = @_;
	my $r = $uref->is_empty('nodes');
	$self->_addlist('users', $uref);
	$uref->_addlist('nodes', $self);
	$self->{usercount} = scalar @{$self->{users}};
	return $r ? ($uref) : ();
}

# delete a user from this node
sub del_user
{
	my ($self, $uref) = @_;

	$self->_dellist('users', $uref);
	$uref->_dellist('nodes', $self);
	$self->{usercount} = scalar @{$self->{users}};
	return $uref->is_empty('nodes') ? ($uref) : ();
}

# add a single dxchan link
sub add_dxchan
{
	my ($self, $dxchan) = @_;
	return $self->_addlist('dxchan', $dxchan);
}

# remove a single dxchan link
sub del_dxchan
{
	my ($self, $dxchan) = @_;
	return $self->_dellist('dxchan', $dxchan);
}

sub usercount
{
	my $self = shift;
	if (@_ && @{$self->{users}} == 0) {
		$self->{usercount} = shift;
	}
	return $self->{usercount};
}

sub users
{
	my $self = shift;
	return @{$self->{users}};
}

sub nodes
{
	my $self = shift;
	return @{$self->{nodes}};
}

sub unlink_all_users
{
	my $self = shift;
	my @rout;
	foreach my $u (${$self->{users}}) {
		my $uref = Route::User::get($u);
		push @rout, $self->del_user($uref) if $uref;
	}
	return @rout;
}

sub new
{
	my $pkg = shift;
	my $call = uc shift;
	
	confess "already have $call in $pkg" if $list{$call};
	
	my $self = $pkg->SUPER::new($call);
	$self->{dxchan} = ref $pkg ? [ $pkg->{call} ] : [ ];
	$self->{version} = shift || 5000;
	$self->{flags} = shift || Route::here(1);
	$self->{users} = [];
	$self->{nodes} = [];
	
	$list{$call} = $self;
	dbg("creating Route::Node $self->{call}") if isdbg('routelow');
	
	return $self;
}

sub delete
{
	my $self = shift;
	dbg("deleting Route::Node $self->{call}") if isdbg('routelow');
	delete $list{$self->{call}};
}

sub get
{
	my $call = shift;
	$call = shift if ref $call;
	my $ref = $list{uc $call};
	dbg("Failed to get Node $call" ) if !$ref && isdbg('routerr');
	return $ref;
}

sub get_all
{
	return values %list;
}

sub DESTROY
{
	my $self = shift;
	my $pkg = ref $self;
	my $call = $self->{call} || "Unknown";
	
	dbg("destroying $pkg with $call") if isdbg('routelow');
	$self->unlink_all_users if @{$self->{users}};
}

#
# generic AUTOLOAD for accessors
#

sub AUTOLOAD
{
	no strict;
	my $name = $AUTOLOAD;
	return if $name =~ /::DESTROY$/;
	$name =~ s/^.*:://o;
  
	confess "Non-existant field '$AUTOLOAD'" unless $valid{$name} || $Route::valid{$name};

	# this clever line of code creates a subroutine which takes over from autoload
	# from OO Perl - Conway
        *$AUTOLOAD = sub {$_[0]->{$name} = $_[1] if @_ > 1; return $_[0]->{$name}};
        goto &$AUTOLOAD;
}

1;

