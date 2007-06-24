#
# A class implimenting LRU sematics with hash look up
#
# Copyright (c) 2002 Dirk Koopman, Tobit Computer Co Ltd 
#
#
#
# The structure of the objects stored are:-
#
#  [next, prev, obj, callsign]
#
# The structure of the base is:-
#
#  [next, prev, max objects, count ]
#
#

package LRU;


use strict;
use Chain;
use DXVars;
use DXDebug;

use vars qw(@ISA);
@ISA = qw(Chain);

sub newbase
{
	my $pkg = shift;
	my $name = shift;
	my $max = shift;
	confess "LRU->newbase requires a name and maximal count" unless $name && $max;
	return $pkg->SUPER::new({ }, $max, 0, $name);
}

sub get
{
	my ($self, $call) = @_;
	if (my $p = $self->obj->{$call}) {
		dbg("LRU $self->[5] cache hit $call") if isdbg('lru');
		$self->rechain($p);
		return $p->obj;
	}
	return undef;
}

sub put
{
	my ($self, $call, $ref) = @_;
	confess("need a call and a reference") unless defined $call && $ref;
	my $p = $self->obj->{$call};
	if ($p) {
		# update the reference and rechain it
		dbg("LRU $self->[5] cache update $call") if isdbg('lru');
		$p->obj($ref);
		$self->rechain($p);
	} else {
		# delete one of the end of the chain if required
		while ($self->[4] >= $self->[3] ) {
			$p = $self->prev;
			my $call = $p->[3];
			dbg("LRU $self->[5] cache LRUed out $call now $self->[4]/$self->[3]") if isdbg('lru');
			$self->remove($call);
		}

		# add a new one
		dbg("LRU $self->[5] cache add $call now $self->[4]/$self->[3]") if isdbg('lru');
		$p = $self->new($ref, $call);
		$self->add($p);
		$self->obj->{$call} = $p;
		$self->[4]++;
	}
}

sub remove
{
	my ($self, $call) = @_;
	my $q = $self->obj->{$call};
	confess("$call is already removed") unless $q;
	dbg("LRU $self->[5] cache remove $call now $self->[4]/$self->[3]") if isdbg('lru');
	$q->obj(1);
	$q->SUPER::del;
	delete $self->obj->{$call};
	$self->[4]--;
}

sub count
{
	return $_[0]->[4];
}

1;
