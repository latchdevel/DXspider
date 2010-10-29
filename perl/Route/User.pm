#
# User routing routines
#
# Copyright (c) 2001 Dirk Koopman G1TLH
#
#
# 

package Route::User;

use DXDebug;
use Route;
use DXUtil;

use strict;

use vars qw(%list %valid @ISA $max $filterdef);
@ISA = qw(Route);

%valid = (
		  parent => '0,Parent Calls,parray',
		  ip => '0,IP Address',
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
	my $flags = shift;
	my $ip = shift;

	confess "already have $call in $pkg" if $list{$call};
	
	my $self = $pkg->SUPER::new($call);
	$self->{parent} = [ $ncall ];
	$self->{flags} = $flags || Route::here(1);
	$self->{ip} = $ip if defined $ip;
	$list{$call} = $self;
	dbg("CLUSTER: user $call added") if isdbg('cluster');

	return $self;
}

sub get_all
{
	return values %list;
}

sub del
{
	my $self = shift;
	my $pref = shift;
	my $call = $self->{call};
	$self->delparent($pref);
	unless (@{$self->{parent}}) {
		delete $list{$call};
		dbg("CLUSTER: user $call deleted") if isdbg('cluster');
		return $self;
	}
	return undef;
}

sub get
{
	my $call = shift;
	$call = shift if ref $call;
	my $ref = $list{uc $call};
	dbg("Failed to get User $call" ) if !$ref && isdbg('routerr');
	return $ref;
}

sub addparent
{
	my $self = shift;
    return $self->_addlist('parent', @_);
}

sub delparent
{
	my $self = shift;
    return $self->_dellist('parent', @_);
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
