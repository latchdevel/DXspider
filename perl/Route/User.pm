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

use vars qw(%list %valid @ISA $max);
@ISA = qw(Route);

%valid = (
		  parent => '0,Parent Calls,parray',
);

%list = ();
$max = 0;

sub count
{
	my $n = scalar %list;
	$max = $n if $n > $max;
	return $n;
}

sub max
{
	return $max;
}

sub new
{
	my $pkg = shift;
	my $call = uc shift;
	my $ncall = uc shift;
	my $flags = shift;
	confess "already have $call in $pkg" if $list{$call};
	
	my $self = $pkg->SUPER::new($call);
	$self->{parent} = [ $ncall ];
	$self->{flags} = $flags;
	$list{$call} = $self;

	return $self;
}

sub del
{
	my $self = shift;
	my $pref = shift;
	my $ref = $self->delparent($pref->{call});
	return () if @$ref;
	delete $list{$self->{call}};
	return ($ref);
}

sub get
{
	my $call = shift;
	$call = shift if ref $call;
	return $list{uc $call};
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

	my $self = shift;
	$name = $AUTOLOAD;
	return if $name =~ /::DESTROY$/;
	$name =~ s/.*:://o;
  
	confess "Non-existant field '$AUTOLOAD'" unless $valid{$name} || $Route::valid{$name};

	# this clever line of code creates a subroutine which takes over from autoload
	# from OO Perl - Conway
#	*{$AUTOLOAD} = sub {@_ > 1 ? $_[0]->{$name} = $_[1] : $_[0]->{$name}} ;
    @_ ? $self->{$name} = shift : $self->{$name} ;
}

1;
