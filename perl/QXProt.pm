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

sub sendallnodes
{
}

sub sendallusers
{

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

sub handleI
{
	my $self = shift;
	
	my @f = split /\^/, $_[2];
	my $inv = Verify->new($f[8]);
	unless ($inv->verify($f[9], $main::me->user->passphrase, $main::mycall, $self->call)) {
		$self->sendnow('D','Sorry...');
		$self->disconnect;
	}
	if ($self->{outbound}) {
		$self->send($self->genI);
	} 
	if ($self->{sort} ne 'S' && $f[5] eq 'DXSpider') {
		$self->{user}->{sort} = $self->{sort} = 'S';
		$self->{user}->{priv} = $self->{priv} = 1 unless $self->{priv};
	}
	$self->{version} = $f[6];
	$self->{build} = $f[7];
	$self->state('init1');
	$self->{lastping} = 0;
}

sub genI
{
	my $self = shift;
	my $inp = Verify->new;
	return frame('I', $self->call, 1, "DXSpider", ($main::version + 53) * 100, $main::build, $inp->challenge, $inp->response($self->user->passphrase, $self->call, $main::mycall));
}

sub handleB
{

}

sub genB
{

}

sub handleP
{

}

sub genP
{

}

sub gen2
{
	my $self = shift;
	
	my $node = shift;
	my $sort = shift;
	my @out;
	my $dxchan;
	
	while (@_) {
		my $str = '';
		for (; @_ && length $str <= 230;) {
			my $ref = shift;
			my $call = $ref->call;
			my $flag = 0;
			
			$flag += 1 if $ref->here;
			$flag += 2 if $ref->conf;
			if ($ref->is_node) {
				my $ping = int($ref->pingave * 10);
				$str .= "^N$flag$call,$ping";
				my $v = $ref->build || $ref->version;
				$str .= ",$v" if defined $v;
			} else {
				$str .= "^U$flag$call";
			}
		}
		push @out, $str if $str;
	}
	my $n = @out;
	my $h = get_hops(90);
	@out = map { sprintf "PC90^%s^%X^%s%d%s^%s^", $node->call, $main::systime, $sort, --$n, $_, $h } @out;
	return @out;
}

1;
