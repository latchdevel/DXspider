#
# Thingy handling
#
# This is the new fundamental protocol engine handler
# 
# This is where all the new things (and eventually all the old things
# as well) happen.
#
# $Id$
#
# Copyright (c) 2004 Dirk Koopman G1TLH
#

use strict;

package Thingy;

use vars qw($VERSION $BRANCH @queue @permin @persec);
$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /\d+\.\d+\.(\d+)\.(\d+)/  || (0,0));
$main::build += $VERSION;
$main::branch += $BRANCH;

@queue = ();					# the input / processing queue

#
# these are set up using the Thingy->add_second_process($addr, $name)
# and Thingy->add_minute_process($addr, $name)
#
# They replace the old cycle in cluster.pl
#

@persec = ();					# this replaces the cycle in cluster.pl
@permin = ();					# this is an extra per minute cycle

my $lastsec = time;
my $lastmin = time;

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
	my $dxchan = shift;
	my $class;
	if (@_) {
		$class = shift;
	} elsif ($dxchan->isa('DXChannel')) {
		$class = ref $dxchan;
	}

	# do output filtering
	if ($thing->can('out_filter')) {
		return unless $thing->out_filter;
	}

	# generate the line which may (or not) be cached
	my @out;
	if (my $ref = $thing->{class}) {
		push @out, ref $ref ? @$ref : $ref;
	} else {
		no strict 'refs';
		my $sub = "gen_$class";
		push @out, $thing->$sub($dxchan) if $thing->can($sub);
	}
	$dxchan->send(@out) if @out;
}

# broadcast to all except @_
sub broadcast
{
	my $thing = shift;
	dbg("Thingy::broadcast: " . $thing->ascii) if isdbg('thing'); 

	foreach my $dxchan (DXChannel::get_all()) {
		next if $dxchan == $main::me;
		next if grep $dxchan == $_, @_;
		$thing->send($dxchan); 
	}
}

# queue this thing for processing
sub queue
{
	my $thing = shift;
	my $dxchan = shift;
	$thing->{dxchan} = $dxchan->call;
	push @queue, $thing;
}

# this is the main commutator loop. In due course it will
# become the *only* commutator loop
sub process
{
	my $thing;
	while (@queue) {
		$thing = shift @queue;
		my $dxchan = DXChannel->get($thing->{dxchan});
		if ($dxchan) {
			if ($thing->can('in_filter')) {
				next unless $thing->in_filter($dxchan);
			}
			$thing->handle($dxchan);
		}
	}

	# per second and per minute processing
	if ($main::systime != $lastsec) {
		if ($main::systime >= $lastmin+60) {
			foreach my $r (@permin) {
				&{$r->[0]}();
			}
			$lastmin = $main::systime;
		}
		foreach my $r (@persec) {
			&{$r->[0]}();
		}
		$lastsec = $main::systime;
	}
}

sub add_minute_process
{
	my $pkg = shift;
	my $addr = shift;
	my $name = shift;
	dbg('Adding $name to Thingy per minute queue');
	push @permin, [$addr, $name];
}

sub add_second_process
{
	my $pkg = shift;
	my $addr = shift;
	my $name = shift;
	dbg('Adding $name to Thingy per second queue');
	push @persec, [$addr, $name];
}


sub ascii
{
	my $thing = shift;
	my $dd = new Data::Dumper([$thing]);
	$dd->Indent(0);
	$dd->Terse(1);
	$dd->Sortkeys(1);
    $dd->Quotekeys($] < 5.005 ? 1 : 0);
	return $dd->Dumpxs;
}
1;

