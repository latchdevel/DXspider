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

main::mkver($VERSION = q$Revision$);

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
use DXUtil;


# we expect all thingies to be subclassed
sub new
{
	my $class = shift;
	my $pkg = ref $class || $class;
	my $thing = {@_};

	$thing->{origin} ||= $main::mycall;
	
	bless $thing, $pkg;
	return $thing;
}

# send it out in the format asked for, if available
sub send
{
	my $thing = shift;
	my $dxchan = shift;
	my $class;
	my $sub;
	
	if (@_) {
		$class = shift;
	} elsif ($dxchan->isa('DXChannel')) {
		$class = ref $dxchan;
	}

	# BEWARE!!!!!
	no strict 'refs';

	# do output filtering
	if ($thing->can('out_filter')) {
		return unless $thing->out_filter($dxchan);
	}

	# before send (and line generation) things
	# function must return true to make the send happen
	$sub = "before_send_$class";
	if ($thing->can($sub)) {
		return unless $thing->$sub($dxchan);
	}
	
	# generate the protocol line which may (or not) be cached
	my $ref;
	unless ($ref = $thing->{class}) {
		$sub = "gen_$class";
		$ref = $thing->$sub($dxchan) if $thing->can($sub);
	}
	$dxchan->send(ref $ref ? @$ref : $ref) if $ref;

	# after send
	if ($thing->can('after_send_all')) {
		$thing->after_send_all($dxchan);
	} else {
		$sub = "after_send_$class";
		$thing->$sub($dxchan) if $thing->can($sub);
	}
}

# 
# This is the main routing engine for the new protocol. Broadcast is a slight
# misnomer, because if it thinks it can route it down one or interfaces, it will.
# 
# It handles anything it recognises as a callsign, sees if it can find it in a 
# routing table, and if it does, then routes the message.
#
# If it can't then it will broadcast it.
#
sub broadcast
{
	my $thing = shift;
	dbg("Thingy::broadcast: " . $thing->ascii) if isdbg('thing'); 

	my @dxchan;
	my $to ||= $thing->{route}; 
	$to	||= $thing->{touser};
	$to ||= $thing->{group};
	if ($to && is_callsign($to) && (my $ref = Route::get($to))) {
		dbg("Thingy::broadcast: routing for $to") if isdbg('thing');
		@dxchan = $ref->alldxchan;
	} else {
		@dxchan = DXChannel::get_all();
	}

	dbg("Thingy::broadcast: offered " . join(',', map {$_->call} @dxchan)) if isdbg('thing');
	
	foreach my $dxchan (@dxchan) {
		next if $dxchan == $main::me;
		next if grep $dxchan == $_, @_;
		next if $dxchan->{call} eq $thing->{origin};
		next if $thing->{user} && !$dxchan->is_user && $dxchan->{call} eq $thing->{user};
		
		dbg("Thingy::broadcast: sending to $dxchan->{call}") if isdbg('thing');
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

#
# this is the main commutator loop. In due course it will
# become the *only* commutator loop, This can be called in one
# of two ways: either with 2 args or with none.
#
# The two arg form is an immediate "queue and handle" and does
# a full cycle, immediately
#
sub process
{
	my $thing;

	if (@_ == 2) {
		$thing = shift;
		$thing->queue(shift);
	}

	while (@queue) {
		$thing = shift @queue;
		my $dxchan = DXChannel::get($thing->{dxchan});
		if ($dxchan) {
			if ($thing->can('in_filter')) {
				next unless $thing->in_filter($dxchan);
			}

			# remember any useful routes
			RouteDB::update($thing->{origin}, $dxchan->{call}, $thing->{hopsaway});
			RouteDB::update($thing->{user}, $dxchan->{call}, $thing->{hopsaway}) if exists $thing->{user};
		
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
	#$dd->Sortkeys(1);
    $dd->Quotekeys($] < 5.005 ? 1 : 0);
	return $dd->Dumpxs;
}

sub add_auth
{
	my $thing = shift;
	my $s = $thing->{'s'} = sprintf "%X", int(rand() * 100000000);
	my $auth = Verify->new("DXSp,$main::mycall,$s,$thing->{v},$thing->{b}");
	$thing->{auth} = $auth->challenge($main::me->user->passphrase);
}

#
# create a generalised reply to a passed thing, if it isn't replyable 
# to then undef is returned
#  
sub new_reply
{
	my $thing = shift;
	my $out;
	
	if ($thing->{group} eq $main::mycall) {
		$out = $thing->new;
		$out->{touser} = $thing->{user} if $thing->{user};
		$out->{group} = $thing->{origin};
	} elsif (DXChannel::get($thing->{group})) {
		$out = $thing->new(user => $thing->{group});
		$out->{touser} = $thing->{user} if $thing->{user};
		$out->{group} = $thing->{origin};
	} elsif ($thing->{touser} && DXChannel::get($thing->{touser})) {
		$out = $thing->new(user => $thing->{touser});
		$out->{group} = $thing->{group};
	}
	return $out;
}
1;

