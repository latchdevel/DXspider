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
	
	$self->send($self->genI);
}

sub normal
{
	if ($_[1] =~ /^PC\d\d\^/) {
		DXProt::normal(@_);
		return;
	}
	my ($sort, $tonode, $fromnode, $msgid, $incs);
	return unless ($sort, $tonode, $fromnode, $msgid, $incs) = $_[1] =~ /^QX([A-Z])\^(\*|[-A-Z0-9]+)\^([-A-Z0-9]+)\^([0-9A-F]{1,4})\^.*\^([0-9A-F]{2})$/;

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

	$_[0]->handle($sort, $tonode, $fromnode, $msgid, $_[1]);
	return;
}

sub handle
{
	no strict 'subs';
	my $self = shift;
	my $sort = shift;
	my $sub = "handle$sort";
	$self->$sub(@_) if $self->can($sub);
	return;
}

sub gen
{
	no strict 'subs';
	my $self = shift;
	my $sort = shift;
	my $sub = "gen$sort";
 	$self->$sub(@_) if $self->can($sub);
	return;
}

my $last_node_update = 0;
my $node_update_interval = 60*15;

sub process
{
	if ($main::systime >= $last_node_update+$node_update_interval) {
#		sendallnodes();
#		sendallusers();
		$last_node_update = $main::systime;
	}
}

sub disconnect
{
	my $self = shift;
	$self->DXProt::disconnect(@_);
}

my $msgid = 1;

sub frame
{
	my $sort = shift;
	my $to = shift || "*";
	my $ht;
	
	$ht = sprintf "%X", $msgid;
	my $line = join '^', "QX$sort", $to, $main::mycall, $ht, @_;
	my $cs = sprintf "%02X", unpack("%32C*", $line) & 255;
	$msgid = 1 if ++$msgid > 0xffff;
	return "$line^$cs";
}

sub send_frame
{
	my $self = shift;
	my $origin = shift;
	for (@_) {
		$self->send(frame('X', undef, $origin == $main::me || $origin->is_user ? '' : $origin->call, $_));
	}
}

sub handleI
{
	my $self = shift;
	
	my @f = split /\^/, $_[3];
	if ($self->user->passphrase && $f[7] && $f[8]) {
		my $inv = Verify->new($f[7]);
		unless ($inv->verify($f[8], $main::me->user->passphrase, $main::mycall, $self->call)) {
			$self->sendnow('D','Sorry...');
			$self->disconnect;
		}
		$self->{verified} = 1;
	} else {
		$self->{verified} = 0;
	}
	if ($self->{outbound}) {
		$self->send($self->genI);
	} 
	if ($self->{sort} ne 'S' && $f[4] eq 'DXSpider') {
		$self->{user}->{sort} = $self->{sort} = 'S';
		$self->{user}->{priv} = $self->{priv} = 1 unless $self->{priv};
	}
	$self->{version} = $f[5];
	$self->{build} = $f[6];
	$self->state('init1');
	$self->{lastping} = 0;
}

sub genI
{
	my $self = shift;
	my @out = ('I', $self->call, "DXSpider", ($main::version + 53) * 100, $main::build);
	if (my $pass = $self->user->passphrase) {
		my $inp = Verify->new;
		push @out, $inp->challenge, $inp->response($pass, $self->call, $main::mycall);
	}
	return frame(@out);
}

sub handleR
{

}

sub genR
{

}

sub handleP
{

}

sub genP
{

}

sub handleX
{
	my $self = shift;
	my ($tonode, $fromnode, $msgid, $line) = @_[0..3];
	my ($origin, $l) = split /\^/, $line, 2;

	my ($pcno) = $l =~ /^PC(\d\d)/;
	if ($pcno) {
		DXProt::normal($self, $l);
	}
}


1;
