#
# Investigate whether an external node is accessible
#
# If it is, make it believable otherwise mark as not
# to be believed. 
#
# It is possible to store up state for a node to be 
# investigated, so that if it is accessible, its details
# will be passed on to whomsoever might be interested.
#
# Copyright (c) 2004 Dirk Koopman, G1TLH
#
# $Id$
#

use strict;

package Investigate;

use DXDebug;
use DXUtil;


use vars qw($VERSION $BRANCH);
$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /\d+\.\d+\.(\d+)\.(\d+)/  || (0,0));
$main::build += $VERSION;
$main::branch += $BRANCH;

use vars qw (%list %valid $pingint $maxpingwait);

$pingint = 5;					# interval between pings for each investigation
								# this is to stop floods of pings
$maxpingwait = 120;				# the maximum time we will wait for a reply to a ping
my $lastping = 0;				# last ping done
%list = ();						# the list of outstanding investigations
%valid = (						# valid fields
		  call => '0,Callsign',
		  start => '0,Started at,atime',
		  version => '0,Node Version',
		  build => '0,Node Build',
		  here => '0,Here?,yesno',
		  conf => '0,In Conf?,yesno',
		  pingsent => '0,Time ping sent,atime',
		  state => '0,State',
		  via => '0,Via Node',
		  pcxx => '0,Stored PCProt,parray',
		 );

my %via = ();

sub new
{
	my $pkg = shift;
	my $call = shift;
	my $via = shift;
	
	my $self = $list{"$via,$call"};
	unless ($self) {
		$self = bless { 
					   call=>$call, 
					   via=>$via,
					   start=>$main::systime,
					   state=>'start',
					   pcxx=>[],
					  }, ref($pkg) || $pkg;
		$list{"$via,$call"} = $self; 
	} 
	dbg("Investigate: New $call via $via") if isdbg('investigate');
	return $self;
}

sub get
{
	return $list{"$_[1],$_[0]"};
}

sub chgstate
{
	my $self = shift;
	my $state = shift;
	dbg("Investigate: $self->{call} via $self->{via} state $self->{state}->$state") if isdbg('investigate');
	$self->{state} = $state;
}

sub handle_ping
{
	my $self = shift;
	dbg("Investigate: ping received for $self->{call} via $self->{via}") if isdbg('investigate');
	if ($self->{state} eq 'waitping') {
		$via{$self->{via}} = 0;       # cue up next ping on this interface
		delete $list{"$self->{via},$self->{call}"};
		my $user = DXUser->get_current($self->{via});
		if ($user) {
			$user->set_believe($self->{call});
			$user->put;
		}
		my $dxchan = DXChannel::get($self->{via});
		if ($dxchan) {
			dbg("Investigate: sending PC19 for $self->{call}") if isdbg('investigate');
			foreach my $pc (@{$self->{pcxx}}) {
				no strict 'refs';
				my $handle = "handle_$pc->[0]";
				dbg("Investigate: sending PC$pc->[0] (" . join(',', @$pc) . ")") if isdbg('investigate');
				my $regex = $pc->[1];
				$regex =~ s/\^/\\^/g;
				DXProt::eph_del_regex($regex);
				$dxchan->$handle(@$pc);
			}
		}
	}
}

sub store_pcxx
{
	my $self = shift;
	dbg("Investigate: Storing (". join(',', @_) . ")") if isdbg('investigate');
	push @{$self->{pcxx}}, [@_];
}

sub process
{
	while (my ($k, $v) = each %list) {
		if ($v->{state} eq 'start') {
			my $via = $via{$v->{via}} || 0;
			if ($main::systime > $via+$pingint) {
				DXProt::addping($main::mycall, $v->{call}, $v->{via});
				$v->{start} = $lastping = $main::systime;
				dbg("Investigate: ping sent to $v->{call} via $v->{via}") if isdbg('investigate');
				$v->chgstate('waitping');
				$via{$v->{via}} = $main::systime;
			}
		} elsif ($v->{state} eq 'waitping') {
			if ($main::systime > $v->{start} + $maxpingwait) {
				dbg("Investigate: ping timed out on $v->{call} via $v->{via}") if isdbg('investigate');
				delete $list{$k};
				my $user = DXUser->get_current($v->{via});
				if ($user) {
					$user->lastping($v->{via}, $main::systime);
					$user->put;
				}
			}
		}
	}
}


sub AUTOLOAD
{
	no strict;
	my $name = $AUTOLOAD;
	return if $name =~ /::DESTROY$/;
	$name =~ s/^.*:://o;
  
	confess "Non-existant field '$AUTOLOAD'" if !$valid{$name};

	# this clever line of code creates a subroutine which takes over from autoload
	# from OO Perl - Conway
	*$AUTOLOAD = sub {@_ > 1 ? $_[0]->{$name} = $_[1] : $_[0]->{$name}};
	goto &$AUTOLOAD;
}
1;
