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
use DXChannel;
use Prefix;

use strict;


use vars qw($VERSION $BRANCH);
$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /\d+\.\d+\.(\d+)\.(\d+)/  || (0,0));
$main::build += $VERSION;
$main::branch += $BRANCH;

use vars qw(%list %valid $filterdef $default_metric);

%valid = (
		  call => "0,Callsign",
		  flags => "0,Flags,phex",
		  dxcc => '0,Country Code',
		  itu => '0,ITU Zone',
		  cq => '0,CQ Zone',
		  state => '0,State',
		  city => '0,City',
		  dxchan => '0,DXChans,parray',
		  links => '0,Node Links,parray',
		 );


$filterdef = bless ([
			  # tag, sort, field, priv, special parser 
			  ['channel', 'c', 0],
			  ['channel_dxcc', 'nc', 1],
			  ['channel_itu', 'ni', 2],
			  ['channel_zone', 'nz', 3],
			  ['call', 'c', 4],
			  ['by', 'c', 4],
			  ['call_dxcc', 'nc', 5],
			  ['by_dxcc', 'nc', 5],
			  ['call_itu', 'ni', 6],
			  ['by_itu', 'ni', 6],
			  ['call_zone', 'nz', 7],
			  ['by_zone', 'nz', 7],
			  ['channel_state', 'ns', 8],
			  ['call_state', 'ns', 9],
			  ['by_state', 'ns', 9],
			 ], 'Filter::Cmd');

$default_metric = 10;

sub new
{
	my ($pkg, $call) = @_;
	$pkg = ref $pkg if ref $pkg;

	my $self = bless {call => $call}, $pkg;
	dbg("create $pkg with $call") if isdbg('routelow');

	# add in all the dxcc, itu, zone info
	my @dxcc = Prefix::extract($call);
	if (@dxcc > 0) {
		$self->{dxcc} = $dxcc[1]->dxcc;
		$self->{itu} = $dxcc[1]->itu;
		$self->{cq} = $dxcc[1]->cq;
		$self->{state} = $dxcc[1]->state;
		$self->{city} = $dxcc[1]->city;
	}
	$self->{flags} = here(1);
	
	return $self; 
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
	my @out;
	foreach my $c (@_) {
		confess "Need a ref here" unless ref($c);
		
		my $call = $c->{call};
		unless (grep $_ eq $call, @{$self->{$field}}) {
			push @{$self->{$field}}, $call;
			dbg(ref($self) . " adding $call to " . $self->{call} . "->\{$field\}") if isdbg('routelow');
			push @out, $c;
		}
	}
	return @out;
}

sub _dellist
{
	my $self = shift;
	my $field = shift;
	my @out;
	foreach my $c (@_) {
		confess "Need a ref here" unless ref($c);
		my $call = $c->{call};
		if (grep $_ eq $call, @{$self->{$field}}) {
			$self->{$field} = [ grep {$_ ne $call} @{$self->{$field}} ];
			dbg(ref($self) . " deleting $call from " . $self->{call} . "->\{$field\}") if isdbg('routelow');
			push @out, $c;
		}
	}
	return @out;
}

sub is_empty
{
	my $self = shift;
	return @{$self->{$_[0]}} == 0;
}

#
# flag field constructors/enquirers
#
# These can be called in various ways:-
#
# Route::here or $ref->here returns 1 or 0 depending on value of the here flag
# Route::here(1) returns 2 (the bit value of the here flag)
# $ref->here(1) or $ref->here(0) sets the here flag
#

sub here
{
	my $self = shift;
	my $r = shift;
	return $self ? 2 : 0 unless ref $self;
	return ($self->{flags} & 2) ? 1 : 0 unless defined $r;
	$self->{flags} = (($self->{flags} & ~2) | ($r ? 2 : 0));
	return $r ? 1 : 0;
}

sub conf
{
	my $self = shift;
	my $r = shift;
	return $self ? 1 : 0 unless ref $self;
	return ($self->{flags} & 1) ? 1 : 0 unless defined $r;
	$self->{flags} = (($self->{flags} & ~1) | ($r ? 1 : 0));
	return $r ? 1 : 0;
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
	my $seen = shift;
	my @out;
	my $line;
	my $call = $self->user_call;
	my $printit = 1;

	# allow ranges
	if (@_) {
		$printit = grep $call =~ m|$_|, @_;
	}

	if ($printit) {
		$line = ' ' x ($level*2) . "$call";
		$call = ' ' x length $call; 
		
		# recursion detector
		if ((DXChannel->get($self->{call}) && $level > 1) || grep $self->{call} eq $_, @$seen) {
			$line .= ' ...';
			push @out, $line;
			return @out;
		}
		push @$seen, $self->{call};

		# print users
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
						$line = ' ' x ($level*2) . "$call->$c ";
					}
				}
			}
		}
		$line =~ s/->$//g;
		$line =~ s/\s+$//;
		push @out, $line if length $line;
	}
	
	# deal with more nodes
	foreach my $ncall (sort @{$self->{links}}) {
		my $nref = Route::Node::get($ncall);

		if ($nref) {
			my $c = $nref->user_call;
#			dbg("recursing from $call -> $c") if isdbg('routec');
			push @out, $nref->config($nodes_only, $level+1, $seen, @_);
		} else {
			push @out, ' ' x (($level+1)*2)  . "$ncall?" if @_ == 0 || (@_ && grep $ncall =~ m|$_|, @_); 
		}
	}

	return @out;
}

sub cluster
{
	my $nodes = Route::Node::count();
	my $tot = Route::User::count();
	my $users = scalar DXCommandmode::get_all();
	my $maxusers = Route::User::max();
	my $uptime = main::uptime();
	
	return " $nodes nodes, $users local / $tot total users  Max users $maxusers  Uptime $uptime";
}

#
# routing things
#

sub get
{
	my $call = shift;
	return Route::Node::get($call) || Route::User::get($call);
}

sub _distance
{
	my $self = shift;
	my $ah = shift;
	my $call = $self->{call};
	
	if (DXChannel->get($call)) {
		my $n = scalar @_ || 0;
		my $o = $ah->{$call} || 9999;
		$ah->{$call} = $n if $n < $o;
		dbg("_distance hit: $call = $n") if isdbg('routech');
		return;
	} 

	dbg("_distance miss $call: " . join(',', @_)) if isdbg('routech');
	
	foreach my $c (@{$self->{links}}) {
		next if $c eq $call || $c eq $main::mycall;
		next if grep $c eq $_, @_;
		
		my $n = get($c);
		_distance($n, $ah, @_, $c);
	}
	return;
}

sub _ordered_routes
{
	my $self = shift;
	my @routes;

	if (exists $self->{dxchan}) {
		dbg("stored routes for $self->{call}: " . join(',', @{$self->{dxchan}})) if isdbg('routech');
		return @{$self->{dxchan}} if exists $self->{dxchan};
	}

	my %ah;
	_distance($self, \%ah);
	
	@routes = sort {$ah{$a} <=> $ah{$b}} keys %ah;
	$self->{dxchan} = \@routes;
	dbg("new routes for $self->{call}: " . join(',', @routes)) if isdbg('routech');
	return @routes;
}

# find all the possible dxchannels which this object might be on
sub alldxchan
{
	my $self = shift;
	my @dxchan;

	my $dxchan = DXChannel->get($self->{call});
	push @dxchan, $dxchan if $dxchan;

	@dxchan = map {DXChannel->get($_)} _ordered_routes($self) unless @dxchan;
	return @dxchan;
}

sub dxchan
{
	my $self = shift;
	
	# ALWAYS return the locally connected channel if present;
	my $dxchan = DXChannel->get($self->call);
	return $dxchan if $dxchan;
	
	my @dxchan = $self->alldxchan;
	return undef unless @dxchan;
	
	# determine the minimum ping channel
	my $minping = 99999999;
	foreach my $dxc (@dxchan) {
		my $p = $dxc->pingave;
		if (defined $p  && $p < $minping) {
			$minping = $p;
			$dxchan = $dxc;
		}
	}
	$dxchan = shift @dxchan unless $dxchan;
	return $dxchan;
}

sub _addlink
{
	my $self = shift;
	delete $self->{dxchan};
    return $self->_addlist('links', @_);
}

sub _dellink
{
	my $self = shift;
	delete $self->{dxchan};
    return $self->_dellist('links', @_);
}

#
# track destruction
#

sub DESTROY
{
	my $self = shift;
	my $pkg = ref $self;
	
	dbg("$pkg $self->{call} destroyed") if isdbg('routelow');
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
	no strict;
	my $name = $AUTOLOAD;
	return if $name =~ /::DESTROY$/;
	$name =~ s/^.*:://o;
  
	confess "Non-existant field '$AUTOLOAD'" if !$valid{$name};

	# this clever line of code creates a subroutine which takes over from autoload
	# from OO Perl - Conway
	*{$AUTOLOAD} = sub {@_ > 1 ? $_[0]->{$name} = $_[1] : $_[0]->{$name}};
       goto &$AUTOLOAD;

}

1;
