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
		  flags => "0,Flags,phex",
		 );

sub new
{
	my ($pkg, $call) = @_;

	dbg('routelow', "create " . (ref($pkg) || $pkg) ." with $call");
	
	return bless {call => $call}, (ref $pkg || $pkg);
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
			dbg('routelow', ref($self) . " adding $call to " . $self->{call} . "->\{$field\}");
		}
	}
	return $self->{$field};
}

sub _dellist
{
	my $self = shift;
	my $field = shift;
	foreach my $c (@_) {
		my $call = _getcall($c);
		if (grep {$_ eq $call} @{$self->{$field}}) {
			$self->{$field} = [ grep {$_ ne $call} @{$self->{$field}} ];
			dbg('routelow', ref($self) . " deleting $call from " . $self->{call} . "->\{$field\}");
		}
	}
	return $self->{$field};
}

#
# flag field constructors/enquirers
#

sub here
{
	my $self = shift;
	my $r = shift;
	return $self ? 2 : 0 unless ref $self;
	return $self->{flags} & 2 unless $r;
	$self->{flags} = (($self->{flags} & ~2) | ($r ? 2 : 0));
	return $r;
}

sub conf
{
	my $self = shift;
	my $r = shift;
	return $self ? 1 : 0 unless ref $self;
	return $self->{flags} & 1 unless $r;
	$self->{flags} = (($self->{flags} & ~1) | ($r ? 1 : 0));
	return $r;
}

# 
# display routines
#

sub user_call
{
	my $self = shift;
	my $call = sprintf "%s", $self->{call};
	return $self->here ? "$call" : "($call)";
}

sub config
{
	my $self = shift;
	my $nodes_only = shift;
	my $level = shift;
	my @out;
	my $line;
	my $call = $self->user_call;

	$line = ' ' x ($level*2) . "$call";
	$call = ' ' x length $call; 
	unless ($nodes_only) {
		if (@{$self->{users}}) {
			$line .= '->';
			foreach my $ucall (sort @{$self->{users}}) {
				my $uref = Route::User::get($ucall);
				my $c;
				if ($uref) {
					$c = $uref->user_call;
				} else {
					$c = "$ucall?";
				}
				if ((length $line) + (length $c) + 1 < 79) {
					$line .= $c . ' ';
				} else {
					$line =~ s/\s+$//;
					push @out, $line;
					$line = ' ' x ($level*2) . "$call->";
				}
			}
		}
	}
	$line =~ s/->$//g;
	$line =~ s/\s+$//;
	push @out, $line if length $line;
	
	foreach my $ncall (sort @{$self->{nodes}}) {
		my $nref = Route::Node::get($ncall);
		next if @_ && !grep $ncall =~ m|$_|, @_;
		
		if ($nref) {
			my $c = $nref->user_call;
			push @out, $nref->config($nodes_only, $level+1, @_);
		} else {
			push @out, ' ' x (($level+1)*2)  . "$ncall?";
		}
	}

	return @out;
}

#
# track destruction
#

sub DESTROY
{
	my $self = shift;
	my $pkg = ref $self;
	
	dbg('routelow', "$pkg $self->{call} destroyed");
}

no strict;
#
# return a list of valid elements 
# 

sub fields
{
	my $pkg = shift;
	$pkg = ref $pkg if ref $pkg;
    my $val = "${pkg}::valid";
	my @out = keys %$val;
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
    my $val = "${pkg}::valid";
	return $val->{$ele} || $valid{$ele};
}

#
# generic AUTOLOAD for accessors
#
sub AUTOLOAD
{
	my $self = shift;
	my $name = $AUTOLOAD;
	return if $name =~ /::DESTROY$/;
	$name =~ s/.*:://o;
  
	confess "Non-existant field '$AUTOLOAD'" if !$valid{$name};

	# this clever line of code creates a subroutine which takes over from autoload
	# from OO Perl - Conway
#	*{$AUTOLOAD} = sub {@_ > 1 ? $_[0]->{$name} = $_[1] : $_[0]->{$name}} ;
    @_ ? $self->{$name} = shift : $self->{$name} ;
}

1;
