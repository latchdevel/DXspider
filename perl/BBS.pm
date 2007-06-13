#!/usr/bin/perl
#
# Sigh, I suppose it had to happen at some point...
#
# This is a simple BBS Forwarding module.
#
# Copyright (c) 1999 - Dirk Koopman G1TLH
#
# $Id$
#

package BBS;

use strict;
use DXUser;
use DXChannel;
use DB_File;
use DXDebug;
use vars qw (@ISA %bid $bidfn $lastbidclean $bidcleanint %hash $maxbidage);

@ISA = qw(DXChannel);

%bid = ();						# the bid hash
$bidfn = "$main::root/msg/bid";	# the bid file filename
$lastbidclean = time;			# the last time the bid file was cleaned
$bidcleanint = 86400;			# the time between bid cleaning intervals
$maxbidage = 60;				# the maximum age of a stored bid

sub init
{
	tie %hash, 'DB_File', $bidfn;
}

#
# obtain a new connection this is derived from dxchannel
#

sub new 
{
	my $self = DXChannel::alloc(@_);
	return $self;
}

#
# start a new connection
#
sub start
{
	my ($self, $line, $sort) = @_;
	my $call = $self->{call};
	my $user = $self->{user};
	
	# remember type of connection
	$self->{consort} = $line;
	$self->{outbound} = $sort eq 'O';
	$self->{priv} = $user->priv;
	$self->{lang} = $user->lang;
	$self->{isolate} = $user->{isolate};
	$self->{consort} = $line;	# save the connection type
	
	# set unbuffered and no echo
	$self->send_now('B',"0");
	$self->send_now('E',"0");
	
	# send initialisation string
    $self->send("[SDX-$main::version-H\$]");
	$self->prompt;
	$self->state('prompt');

	Log('BBS', "$call", "connected");
}

#
# send a prompt
#

sub prompt
{
	my $self = shift;
	$self->send("$main::mycall>");
}

#
# normal processing
#

sub normal
{
	my ($self, $line) = @_;

    my ($com, $rest) = split /\s+/, $line, 2;
	$com = uc $com;
	if ($com =~ /^S/) {
        my ($to, $at, $from) = $rest =~ /^(\w+)\s*\@\s*([\#\w\.]+)\s*<\s*(\w+)/;
		my ($bid) = $rest =~ /\$(\S+)$/;
		my ($justat, $haddr) = $at =~ /^(\w+)\.(.*)$/;
		$justat = $at unless $justat;
		unless ($to) {
			$self->send('N - no "to" address');
			return;
		}
		unless ($from) {
			$self->send('N - no "from" address');
			return;
		}

		# now handle the different types of send
		if ($com eq 'SB') {
			if ($to =~ /^ALL/) {
				$self->send('N - "ALL" not allowed');
				return;
			}
		} else {
		}
    } elsif ($com =~ /^F/) {
		$self->disconnect;
	} elsif ($com =~ /^(B|Q)/) {
		$self->disconnect;
	}
}

#
# end a connection (called by disconnect)
#
sub disconnect
{
	my $self = shift;
	my $call = $self->call;
	Log('BBS', "$call", "disconnected");
	$self->SUPER::disconnect;
}

# 
# process (periodic processing)
#

sub process
{

}

1;

