#
# Thingy handling
#
# This is the new fundamental protocol engine handler
#
# $Id$
#
# Copyright (c) 2004 Dirk Koopman G1TLH
#

use strict;

package Thingy;

use DXChannel;
use DXDebug;

# we expect all thingies to be subclassed
sub new
{
	my $class = shift;
	my $thing = {@_};
	
	bless $thing, $class;
	return $thing;
}

# send it out in the format asked for, if available
sub send
{
	my $thing = shift;
	my $chan = shift;
	my $class;
	if (@_) {
		$class = shift;
	} elsif ($chan->isa('DXChannel')) {
		$class = ref $chan;
	}

	# generate the line which may (or not) be cached
	my @out;
	if (my $ref = $thing->{class}) {
		push @out, ref $ref ? @$ref : $ref;
	} else {
		no strict 'refs';
		my $sub = "gen_$class";
		push @out, $thing->$sub() if $thing->can($sub);
	}
	$chan->send(@out) if @out;
}


1;

