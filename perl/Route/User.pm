#
# User routing routines
#
# Copyright (c) 2001 Dirk Koopman G1TLH
#
# $Id$
# 

package Route::User;

use DXDebug;
use Route;

use strict;

use vars qw($VERSION $BRANCH);
$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /:\s+(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /:\s+\d+\.\d+\.(\d+)\.(\d+)/  || (0,0));
$main::build += $VERSION;
$main::branch += $BRANCH;

use vars qw(%list %valid @ISA $max $filterdef);
@ISA = qw(Route);

%valid = (
		  dxchan => '0,Dxchan List,parray',
		  nodes => '0,On Node(s),parray',
);

$filterdef = $Route::filterdef;
%list = ();
$max = 0;

sub count
{
	my $n = scalar(keys %list);
	$max = $n if $n > $max;
	return $n;
}

sub max
{
	count();
	return $max;
}

sub new
{
	my $pkg = shift;
	my $call = uc shift;
	my $ncall = uc shift;
	my $flags = shift || Route::here(1);
	confess "already have $call in $pkg" if $list{$call};
	
	my $self = $pkg->SUPER::new($call);
	$self->{nodes} = [ ];
	$self->{flags} = $flags;
	$list{$call} = $self;

	return $self;
}

sub delete
{
	my $self = shift;
	dbg("deleting Route::User $self->{call}") if isdbg('routelow');
	delete $list{$self->{call}};
}

sub get_all
{
	return values %list;
}

sub get
{
	my $call = shift;
	$call = shift if ref $call;
	my $ref = $list{uc $call};
	dbg("Failed to get User $call" ) if !$ref && isdbg('routerr');
	return $ref;
}

# add a user to this node
# returns Route::User if it is a new user;
sub add_node
{
	my ($self, $nref) = @_;
	my $r = $self->is_empty('nodes');
	$self->_addlist('nodes', $nref);
	$nref->_addlist('users', $self);
	$nref->{usercount} = scalar @{$nref->{users}};
	return $r ? ($self) : ();
}

# delete a user from this node
sub del_user
{
	my ($self, $nref) = @_;

	$self->_dellist('nodes', $nref);
	$nref->_dellist('users', $self);
	$nref->{usercount} = scalar @{$nref->{users}};
	return $self->is_empty('nodes') ? ($self) : ();
}

sub nodes
{
	my $self = shift;
	return @{$self->{nodes}};
}

#
# generic AUTOLOAD for accessors
#

sub AUTOLOAD
{
	no strict;
	my ($pkg,$name) = $AUTOLOAD =~ /^(.*)::(\w+)$/;
	return if $name eq 'DESTROY';
  
	confess "Non-existant field '$AUTOLOAD'" unless $valid{$name} || $Route::valid{$name};

	# this clever line of code creates a subroutine which takes over from autoload
	# from OO Perl - Conway
	*$AUTOLOAD = sub {$_[0]->{$name} = $_[1] if @_ > 1; return $_[0]->{$name}};
	goto &$AUTOLOAD;	
#	*{"${pkg}::$name"} = sub {$_[0]->{$name} = $_[1] if @_ > 1; return $_[0]->{$name}};
#	goto &{"${pkg}::$name"};	
}

1;
