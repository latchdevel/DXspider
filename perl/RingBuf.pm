#
# Finite size ring buffer creation and access routines
#
# Copyright (c) - 1998 Dirk Koopman G1TLH
#
#
#

use strict;

package RingBuf;


sub new
{
	my $pkg = shift;
	my $size = shift;

	# 0 - size
	# 1 - lth
	# 2 - end
	# 3 - start
	# 4 - pos
	# 5 - buffer []
	return bless [$size+1, 0, 0, 0, 0, []], (ref $pkg || $pkg);
}

sub write
{
	my $self = shift;

	$self->[5]->[$self->[2]++] = shift;
	$self->[2] = 0 if $self->[2] >= $self->[0];
	$self->[1]++ if $self->[1] < $self->[0];
	if ($self->[1] == $self->[0] && $self->[2] == $self->[3]) {
		$self->[3] = $self->[2]+1;
		$self->[3] = 0 if $self->[3] >= $self->[0]; 
	}
}

sub read
{
	my $self = shift;
	return unless $self->[1];
	my $r;
	
	if ($self->[4] != $self->[2]) {
		$r = $self->[5]->[$self->[4]++];
		$self->[4] = 0 if $self->[4] >= $self->[0];
	}
	return $r;
}

sub rewind
{
	my $self = shift;
	$self->[4] = $self->[3];
}

sub lth
{
	my $self = shift;
	return $self->[1];
}

sub readall
{
	my $self = shift;
	my @out;
	
	$self->rewind;
	while (my $r = $self->read) {
		push @out, $r;
	}
	return @out;
}
1;
