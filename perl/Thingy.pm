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

use vars qw($VERSION $BRANCH);
$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /\d+\.\d+\.(\d+)\.(\d+)/  || (0,0));
$main::build += $VERSION;
$main::branch += $BRANCH;


use DXChannel;
use DXDebug;

use vars qw(@queue);
@queue = ();					# the thingy queue

# we expect all thingies to be subclassed
sub new
{
	my $class = shift;
	my $self = {@_};
	
	bless $self, $class;
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

	$t->process if $t;
}

1;

