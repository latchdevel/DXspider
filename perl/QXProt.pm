#
# This module impliments the new protocal mode for a dx cluster
#
# Copyright (c) 2001 Dirk Koopman G1TLH
#
# $Id$
# 

package QXProt;

@ISA = qw(DXChannel DXProt);

use DXUtil;
use DXChannel;
use DXUser;
use DXM;
use DXLog;
use Spot;
use DXDebug;
use Filter;
use DXDb;
use AnnTalk;
use Geomag;
use WCY;
use Time::HiRes qw(gettimeofday tv_interval);
use BadWords;
use DXHash;
use Route;
use Route::Node;
use Script;
use DXProt;
use Verify;

# sub modules
use QXProt::QXI;
use QXProt::QXP;
use QXProt::QXR;

use strict;

use vars qw($VERSION $BRANCH);
$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /\d+\.\d+\.(\d+)\.(\d+)/  || (0,0));
$main::build += $VERSION;
$main::branch += $BRANCH;

sub init
{
	my $user = DXUser->get($main::mycall);
	$DXProt::myprot_version += $main::version*100;
	$main::me = QXProt->new($main::mycall, 0, $user); 
	$main::me->{here} = 1;
	$main::me->{state} = "indifferent";
	$main::me->{sort} = 'S';    # S for spider
	$main::me->{priv} = 9;
	$main::me->{metric} = 0;
	$main::me->{pingave} = 0;
	$main::me->{registered} = 1;
	$main::me->{version} = $main::version;
	$main::me->{build} = $main::build;
		
#	$Route::Node::me->adddxchan($main::me);
}

sub start
{
	my $self = shift;
	$self->SUPER::start(@_);
}

sub sendinit
{
	my $self = shift;
	
	$self->send($self->QXI::gen);
}

sub normal
{
	if ($_[1] =~ /^PC\d\d\^/) {
		DXProt::normal(@_);
		return;
	}
	my ($sort, $tonode, $fromnode, $msgid, $line, $incs);
	return unless ($sort, $tonode, $fromnode, $msgid, $line, $incs) = $_[1] =~ /^QX([A-Z])\^(\*|[-A-Z0-9]+)\^([-A-Z0-9]+)\^([0-9A-F]{1,4})\^(.*)\^([0-9A-F]{2})$/;

	$msgid = hex $msgid;
	my $noderef = Route::Node::get($fromnode);
	$noderef = Route::Node::new($fromnode) unless $noderef;

	my $il = length $incs; 
	my $cs = sprintf("%02X", unpack("%32C*", substr($_[1], 0, length($_[1]) - ($il+1))) & 255);
	if ($incs ne $cs) {
		dbg("QXPROT: Checksum fail in: $incs ne calc: $cs" ) if isdbg('chanerr');
		return;
	}

	return unless $noderef->newid($msgid);

	{
		no strict 'subs';
		my $sub = "QX${sort}::handle";
		$_[0]->$sub($tonode, $fromnode, $msgid, $line) if $_[0]->can($sub);
	}
	return;
}

my $last_node_update = 0;
my $node_update_interval = 60*15;

sub process
{
	
	my $t = $main::systime;
	
	foreach my $dxchan (DXChannel->get_all()) {
		next unless $dxchan->is_np;
		next if $dxchan == $main::me;

		# send a ping out on this channel
		if ($dxchan->{pingint} && $t >= $dxchan->{pingint} + $dxchan->{lastping}) {
			if ($dxchan->{nopings} <= 0) {
				$dxchan->disconnect;
			} else {
				$dxchan->addping($main::mycall, $dxchan->call);
				$dxchan->{nopings} -= 1;
				$dxchan->{lastping} = $t;
			}
		}
	}

	if ($t >= $last_node_update+$node_update_interval) {
#		sendallnodes();
#		sendallusers();
		$last_node_update = $main::systime;
	}
}

sub adjust_hops
{
	return $_[1];
}

sub disconnect
{
	my $self = shift;
	$self->DXProt::disconnect(@_);
}

my $msgid = 1;

sub frame
{
	my $self = shift;
	my $sort = shift;
	my $to = shift || "*";
	my $ht;
	
	$ht = sprintf "%X", $msgid;
	my $line = join '^', "QX$sort", $to, $main::mycall, $ht, @_;
	my $cs = sprintf "%02X", unpack("%32C*", $line) & 255;
	$msgid = 1 if ++$msgid > 0xffff;
	return "$line^$cs";
}

# add a ping request to the ping queues
sub addping
{
	my ($self, $usercall, $to) = @_;
	my $ref = $DXChannel::pings{$to} || [];
	my $r = {};
	$r->{call} = $usercall;
	$r->{t} = [ gettimeofday ];
	DXChannel::route(undef, $to, $self->QXP::gen($to, 1, $usercall, @{$r->{t}}));
	push @$ref, $r;
	$DXCHannel::pings{$to} = $ref;
}



1;
