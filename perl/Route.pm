#!/usr/bin/perl
#
# This module impliments the abstracted routing for all protocols and
# is probably what I SHOULD have done the first time. 
#
# Heyho.
#
# This is just a container class which I expect to subclass 
#
# Copyright (c) 2001 Dirk Koopman G1TLH
#
# $Id$
# 

package Route;

use DXDebug;

use strict;

use vars qw(%list %valid);

%valid = (
		  call => "0,Callsign",
		 );

sub new
{
	my ($pkg, $call) = @_;
	dbg('route', "$pkg created $call");
	return bless {call => $call}, $pkg;
}

#
# get a callsign from a passed reference or a string
#

sub _getcall
{
	my $self = shift;
	my $thingy = shift;
	$thingy = $self unless $thingy;
	$thingy = $thingy->call if ref $thingy;
	$thingy = uc $thingy if $thingy;
	return $thingy;
}

# 
# add and delete a callsign to/from a list
#

sub _addlist
{
	my $self = shift;
	my $field = shift;
	foreach my $c (@_) {
		my $call = _getcall($c);
		unless (grep {$_ eq $call} @{$self->{$field}}) {
			push @{$self->{$field}}, $call;
			dbg('route', ref($self) . " adding $call to " . $self->{call} . "->\{$field\}");
		}
	}
}

sub _dellist
{
	my $self = shift;
	my $field = shift;
	foreach my $c (@_) {
		my $call = _getcall($c);
		if (grep {$_ eq $call} @{$self->{$field}}) {
			$self->{$field} = [ grep {$_ ne $call} @{$self->{$field}} ];
			dbg('route', ref($self) . " deleting $call from " . $self->{call} . "->\{$field\}");
		}
	}
}

#
# track destruction
#

sub DESTROY
{
	my $self = shift;
	my $pkg = ref $self;
	
	dbg('route', "$pkg $self->{call} destroyed");
}

no strict;
#
# return a list of valid elements 
# 

sub fields
{
	my $pkg = shift;
	my @out, keys %pkg::valid if ref $pkg;
	push @out, keys %valid;
	return @out;
}

#
# return a prompt for a field
#

sub field_prompt
{ 
	my ($self, $ele) = @_;
	my $pkg = ref $self;
	return $pkg::valid{$ele} || $valid{$ele};
}

#
# generic AUTOLOAD for accessors
#
sub AUTOLOAD
{
	my $self = shift;
	my ($pkg, $name) = $AUTOLOAD =~ /^(.*)::([^:]*)$/;
	return if $name eq 'DESTROY';
  
	confess "Non-existant field '$AUTOLOAD'" unless $valid{$name} || $pkg::valid{$name};

	# this clever line of code creates a subroutine which takes over from autoload
	# from OO Perl - Conway
	*{$AUTOLOAD} = sub {@_ > 1 ? $_[0]->{$name} = $_[1] : $_[0]->{$name}} ;
    @_ ? $self->{$name} = shift : $self->{$name} ;
}

1;
