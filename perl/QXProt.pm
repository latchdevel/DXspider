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

use strict;

use vars qw($VERSION $BRANCH);
$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /\d+\.\d+\.(\d+)\.(\d+)/ ) || 0;
$main::build += $VERSION;
$main::branch += $BRANCH;

use vars qw($last_node_update $node_update_interval);

$node_update_interval = 14*60;
$last_node_update = time;


sub start
{
	my $self = shift;
	$self->SUPER::start(@_);
}

sub normal
{
	if ($_[1] =~ /^PC\d\d\^/) {
		DXProt::normal(@_);
		return;
	}
	my $pcno;
	return unless ($pcno) = $_[1] =~ /^QX(\d\d)\^/;

	my ($self, $line) = @_;
	
	# calc checksum
	$line =~ s/\^(\d\d)$//;
	my $incs = hex $1;
	my $cs = unpack("%32C*", $line) % 255;
	if ($incs != $cs) {
		dbg("QXPROT: Checksum fail in: $incs ne calc: $cs" ) if isdbg('qxerr');
		return;
	}

	# split the field for further processing
	my ($id, $tonode, $fromnode, @field) = split /\^/, $line;
	
}

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
	my $nodes = join(',', map {sprintf("%s:%d", $_->{call}, int($_->{pingave} * $_->{metric}))} DXChannel::get_all_nodes());
	my $users = DXChannel::get_all_users();
	DXChannel::broadcast_nodes(frame(2, undef, undef, hextime(), $users, 'S', $nodes))
}

sub sendallusers
{

}

sub hextime
{
	my $t = shift || $main::systime;
	return sprintf "%X", $t; 
}

sub frame
{
	my $pcno = shift;
	my $to = shift || '';
	my $from = shift || $main::mycall;
	
	my $line = join '^', sprintf("QX%02d", $pcno), $to, $from, @_;
	my $cs = unpack("%32C*", $line) % 255;
	return $line . sprintf("^%02X", $cs);
}

1;
