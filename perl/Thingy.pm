#
# Thingy handling
#
# This is the new fundamental protocol engine handler
#
# $Id$
#
# Copyright (c) 2004 Dirk Koopman G1TLH
#

package Thingy;

use strict;

use vars qw($VERSION $BRANCH);
$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /\d+\.\d+\.(\d+)\.(\d+)/,(0,0));
$main::build += $VERSION;
$main::branch += $BRANCH;


use DXChannel;
use DXDebug;

use Thingy::Route;

use vars qw(@queue);
@queue = ();					# the thingy queue

# we expect all thingies to be subclassed
sub new
{
	my $class = shift;
	my $self = {@_};
	
	my ($type) = $class =~ /::(\w+)$/;
	
	bless $self, $class;
	$self->{_tonode} ||= '*';
	$self->{_fromnode} ||= $main::mycall;
	$self->{_hoptime} ||= 0;
	while (my ($k,$v) = each %$self) {
		delete $self->{$k} unless defined $v;
	}
	return $self;
}

# add the Thingy to the queue
sub add
{
	push @queue, shift;
}

# dispatch Thingies to action it.
sub process
{
	my $t = pop @queue if @queue;

	if ($t) {

		# go directly to this class's t= handler if there is one
		my $type = $t->{t};
		if ($type) {
			# remove extraneous characters put there by the ungodly
			$type =~ s/[^\w]//g;
			$type = 'handle_' . $type;
			if ($t->can($type)) {
				no strict 'refs';
				$t->$type;
				return;
			}
		}
		$t->normal;
	}
}

1;

