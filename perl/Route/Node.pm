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

use strict;

use vars qw(%list %valid @ISA $me);
@ISA = qw(Route);

%valid = (
		  dxchancall => '0,DXChannel Calls,parray',
		  parent => '0,Parent Calls,parray',
		  version => '0,Version',
);

%list = ();

sub init
{
	$me = Route::Node->new(@_);
}

sub new
{
	my $pkg = shift;
	my $call = uc shift;
	confess "already have $call in $pkg" if $list{$call};
	
	my $self = $pkg->SUPER::new($call);
	$self->{dxchancall} = [ ];
	$self->{parent} = [ ];
	$self->{version} = shift;
	
	$list{$call} = $self;
	
	return $self;
}

sub get
{
	my $call = shift;
	$call = shift if ref $call;
	return $list{uc $call};
}

sub adddxchan
{
	my $self = shift;
    $self->_addlist('dxchancall', @_);
}

sub deldxchan
{
	my $self = shift;
    $self->_dellist('dxchancall', @_);
}

sub addparent
{
	my $self = shift;
    $self->_addlist('parent', @_);
}

sub delparent
{
	my $self = shift;
    $self->_dellist('parent', @_);
}

1;

