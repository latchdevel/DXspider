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

use vars qw(%list %valid @ISA);
@ISA = qw(Route);

%valid = (
		  node => '0,Node Calls,parray',
);

%list = ();

sub new
{
	my $pkg = shift;
	my $call = uc shift;
	confess "already have $call in $pkg" if $list{$call};
	
	my $self = $pkg->SUPER::new($call);
	$self->{node} = [ ];
	$list{$call} = $self;
	
	return $self;
}

sub get
{
	my $call = shift;
	$call = shift if ref $call;
	return $list{uc $call};
}

sub addnode
{
	my $self = shift;
    $self->_addlist('node', @_);
}

sub delnode
{
	my $self = shift;
    $self->_dellist('node', @_);
}

1;
