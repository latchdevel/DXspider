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

use vars qw(%list %valid @ISA $max $filterdef);
@ISA = qw(Route);

%valid = (
		  parent => '0,Parent Calls,parray',
		  nodes => '0,Nodes,parray',
		  users => '0,Users,parray',
		  usercount => '0,User Count',
		  version => '0,Version',
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
	return $max;
}

#
# this routine handles the possible adding of an entry in the routing
# table. It will only add an entry if it is new. It may have all sorts of
# other side effects which may include fixing up other links.
#
# It will return a node object if (and only if) it is a completely new
# object with that callsign. The upper layers are expected to do something
# sensible with this!
#
# called as $parent->add(call, dxchan, version, flags) 
#

sub add
{
	my $parent = shift;
	my $call = uc shift;
	confess "Route::add trying to add $call to myself" if $call eq $parent->{call};
	my $self = get($call);
	if ($self) {
		$self->_addparent($parent->{call});
		$parent->_addnode($call);
		return undef;
	}
	$parent->_addnode($call);
	$self = $parent->new($call, @_);
	return $self;
}

#
# this routine is the opposite of 'add' above.
#
# It will return an object if (and only if) this 'del' will remove
# this object completely
#

sub del
{
	my $self = shift;
	my $pref = shift;

	# delete parent from this call's parent list
	my $pcall = $pref->{call};
	my $ref = $self->_delparent($pcall);
	my @nodes;
	
	# is this the last connection, I have no parents anymore?
	unless (@$ref) {
		my $ncall = $self->{call};
		foreach my $rcall (@{$self->{nodes}}) {
			next if grep $rcall eq $_, @_;
			my $r = Route::Node::get($rcall);
			push @nodes, $r->del($self, $ncall, @_) if $r;
		}
		$self->_del_users;
		delete $list{$self->{call}};
		push @nodes, $self;
	}
	return @nodes;
}

sub del_nodes
{
	my $parent = shift;
	my @out;
	foreach my $rcall (@{$parent->{nodes}}) {
		my $r = get($rcall);
		push @out, $r->del($parent, $parent->{call}, @_) if $r;
	}
	return @out;
}

sub _del_users
{
	my $self = shift;
	for (@{$self->{users}}) {
		my $ref = Route::User::get($_);
		$ref->del($self) if $ref;
	}
	$self->{users} = [];
}

# add a user to this node
sub add_user
{
	my $self = shift;
	my $ucall = shift;
	$self->_adduser($ucall);

	$self->{usercount} = scalar @{$self->{users}};
	my $uref = Route::User::get($ucall);
	my @out = (Route::User->new($ucall, $self->{call}, @_)) unless $uref;
	return @out;
}

# delete a user from this node
sub del_user
{
	my $self = shift;
	my $ucall = shift;
	my $ref = Route::User::get($ucall);
	$self->_deluser($ucall);
	my @out = $ref->del($self) if $ref;
	return @out;
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

sub rnodes
{
	my $self = shift;
	my @out;
	foreach my $call (@{$self->{nodes}}) {
		next if grep $call eq $_, @_;
		push @out, $call;
		my $r = get($call);
		push @out, $r->rnodes($call, @_) if $r;
	}
	return @out;
}


sub new
{
	my $pkg = shift;
	my $call = uc shift;
	
	confess "already have $call in $pkg" if $list{$call};
	
	my $self = $pkg->SUPER::new($call);
	$self->{parent} = ref $pkg ? [ $pkg->{call} ] : [ ];
	$self->{version} = shift;
	$self->{flags} = shift;
	$self->{users} = [];
	$self->{nodes} = [];
	
	$list{$call} = $self;
	
	return $self;
}

sub get
{
	my $call = shift;
	$call = shift if ref $call;
	my $ref = $list{uc $call};
	dbg('routerr', "Failed to get Node $call" ) unless $ref;
	return $ref;
}

sub get_all
{
	return values %list;
}

sub _addparent
{
	my $self = shift;
    return $self->_addlist('parent', @_);
}

sub _delparent
{
	my $self = shift;
    return $self->_dellist('parent', @_);
}


sub _addnode
{
	my $self = shift;
    return $self->_addlist('nodes', @_);
}

sub _delnode
{
	my $self = shift;
    return $self->_dellist('nodes', @_);
}


sub _adduser
{
	my $self = shift;
    return $self->_addlist('users', @_);
}

sub _deluser
{
	my $self = shift;
    return $self->_dellist('users', @_);
}

sub DESTROY
{
	my $self = shift;
	my $pkg = ref $self;
	my $call = $self->{call} || "Unknown";
	
	dbg('route', "destroying $pkg with $call");
}

#
# generic AUTOLOAD for accessors
#

sub AUTOLOAD
{
	no strict;

	my $self = shift;
	$name = $AUTOLOAD;
	return if $name =~ /::DESTROY$/;
	$name =~ s/.*:://o;
  
	confess "Non-existant field '$AUTOLOAD'" unless $valid{$name} || $Route::valid{$name};

	# this clever line of code creates a subroutine which takes over from autoload
	# from OO Perl - Conway
#	print "AUTOLOAD: $AUTOLOAD\n";
#	*{$AUTOLOAD} = sub {my $self = shift; @_ ? $self->{$name} = shift : $self->{$name}} ;
    @_ ? $self->{$name} = shift : $self->{$name} ;
}

1;

