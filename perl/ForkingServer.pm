#!/usr/bin/perl -w
#
# This is a forking server class (ofcourse it is :-)
#
# You can only have one of these running at a time, so there!
#
# I am not using AUTOLOAD at the moment in a general spirit
# of 'inat' (a wonderfully succinct serbo-croat word and state
# of being) - So there! Yah boo sucks! Won't! Nurps! 
#
# Can I just say (as a policy statement) that I hope I never have
# to write any more C code (other than to extend or interface to perl).
#
# Copyright (c) 1999 - Dirk Koopman, Tobit Computer Co Ltd
#
# $Id$
#

package ForkingServer;

use strict;

use IO::File;
use IO::Socket;
use Net::hostent;

use Carp;

sub new
{
	my $type = shift;
	my $self = {};
	my $s = shift;
	if ($s) {
		if (ref $s) {
			$self->{child} = $s;
		} else {
			$self->{child} = eval $s;
			confess $@ if $@;
		}
	}
	$self->{port} = shift || 9000;
	$self->{sort} = 'tcp';
	$self->{sorry} = "Bog OFF!\n";
	$self->{allow} = [ '^localhost\$', '^127.0.0' ];
	return bless $self, $type;
}

sub port
{
	my $self = shift;
	my $port = shift;
	$self->{port} = $port;
}

sub sort
{
	my $self = shift;
	my $sort = shift;
	confess "sort must be tcp or udp" unless $sort eq 'tcp' || $sort eq 'udp'; 
	$self->{sort} = $sort;
}

sub allow
{
	my $self = shift;
	$self->{allow} = ref $_[0] ? shift : [ @_ ];
}

sub deny
{
	my $self = shift;
	$self->{deny} = ref $_[0] ? shift : [ @_ ];
}

sub sorry
{
	my $self = shift;
	$self->{sorry} = shift;
}

sub quiet
{
	my $self = shift;
	$self->{quiet} = shift;
}

sub is_parent
{
	my $self = shift;
	return $self->{parent};
}

sub run {
	my $self = shift;
	
	my $server = IO::Socket::INET->new( Proto     => $self->{sort},
										LocalPort => $self->{port},
										Listen    => SOMAXCONN,
										Reuse     => 1);

	my $client;
	
	confess "bot: can't setup server $!" unless $server;
	print "[Server $0 accepting clients on port $self->{port}]\n" unless $self->{quiet};
	
	$SIG{CHLD} = \&reaper;
	$self->{parent} = 1;
	
	while ($client = $server->accept()) {
		$client->autoflush(1);
		my $hostinfo = gethostbyaddr($client->peeraddr);
		my $hostname = $hostinfo->name;
		my $ipaddr = $client->peerhost;
		unless ($self->{quiet}) {
			printf ("[Connect from %s %s]\n", $hostname, $ipaddr);
		}
		if ($self->{allow} && @{$self->{allow}}) {
			unless ((grep { $hostname =~ /$_/ } @{$self->{allow}}) || (grep { $ipaddr =~ /$_/ } @{$self->{allow}})) {
				print "{failed on allow}\n" unless $self->{quiet};
				$client->print($self->{sorry});
				$client->close;
				next;
			}
		}
		if ($self->{deny} && @{$self->{deny}}) {
			if ((grep { $hostname =~ /$_/ } @{$self->{deny}}) || (grep { $ipaddr =~ /$_/ } @{$self->{deny}})) {
				print "{failed on deny}\n" unless $self->{quiet};
				$client->print($self->{sorry});
				$client->close;
				next;
			}
		}
		
		# fork off a copy of myself, we don't exec, merely carry on regardless
		# in the forked program, that should mean that we use the minimum of extra
		# resources 'cos we are sharing everything already.
		my $pid = fork();
		die "bot: can't fork" unless defined $pid;
		if ($pid) {
			
			# in parent
			print "{child $pid created}\n" unless $self->{quiet};
			close $client;
		} else {
			
			# in child
			$SIG{'INT'} = $SIG{'TERM'} = $SIG{CHLD} = 'DEFAULT';
			$server->close;
			delete $self->{parent};
			die "No Child function defined" unless $self->{child} && ref $self->{child};
			&{$self->{child}}($client);
			$client->close;
			return;			
		}
	}
}

sub reaper {
	my $child;
	$child = wait;
	$SIG{CHLD} = \&reaper;  # still loathe sysV
}

1;




