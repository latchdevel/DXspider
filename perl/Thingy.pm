#
# This module is part of the new structure of the cluster
#
# What happens when a sentence comes in is that it is sanity
# checked and then is converted into a Thingy. This Thingy is what 
# is the passed around the system.
#
# Copyright (c) 2001 Dirk Koopman G1TLH
#
# $Id$
# 

use strict;

package Thingy;

use DXDebug;

use vars qw($VERSION $BRANCH %valid);
$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /\d+\.\d+\.(\d+)\.(\d+)/  || (0,0));
$main::build += $VERSION;
$main::branch += $BRANCH;

%valid = (
		  tonode => '0,To Node',
		  fromnode => '0,From Node',
		  fromchan => '0,DXChannel Ref',
		  pcline => '0,Original PC Line',
		  qxline => '0,Original QX Line',
		  hops => '0,Hops',
		 );

sub _valid
{
	my @pkg = split /::/, ref shift;
	my $field = shift;

	# iterate down the packages looking for a 'valid' 
	no strict 'refs';
	while (@pkg >= 1) {
		my $n = join('::'. @pkg, 'valid');
		my $r = $$n{$field};
		return $r if defined $r;
		pop @pkg;
	}
	return undef;
}

sub new
{
	my $pkg = shift;
	my $self = bless {}, $pkg;
	while (my ($k, $v) = each %{\@_}) {
		confess "Non-existant field '$k'" unless $self->_valid($k);
		$self->{lc $k} = $v;
	}
	return $self;
}

sub AUTOLOAD
{
	my $self = shift;
	no strict;
	my $name = $AUTOLOAD;
	return if $name =~ /::DESTROY$/;
	$name =~ s/^.*:://o;
  
	confess "Non-existant field '$AUTOLOAD'" unless $self->_valid($name);

	*$AUTOLOAD = sub {@_ > 1 ? $_[0]->{$name} = $_[1] : $_[0]->{$name}};
	&$AUTOLOAD($self, @_);
}










1;
