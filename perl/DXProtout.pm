#!/usr/bin/perl
#
# This module impliments the outgoing PCxx generation routines
#
# These are all the namespace of DXProt and are separated for "clarity"
#
# Copyright (c) 1998 Dirk Koopman G1TLH
#
# $Id$
# 

package DXProt;

@ISA = qw(DXProt DXChannel);

use DXUtil;
use DXM;
use Carp;

use strict;

#
# All the PCxx generation routines
#

# create a talk string ($from, $to, $via, $text)
sub pc10
{
	my ($from, $to, $via, $text) = @_;
	my $user2 = $via ? $to : ' ';
	my $user1 = $via ? $via : $to;
	$text = unpad($text);
	$text = ' ' if !$text;
	return "PC10^$from^$user1^$text^*^$user2^$main::mycall^~";  
}

# create a dx message (call, freq, dxcall, text) 
sub pc11
{
	my ($mycall, $freq, $dxcall, $text) = @_;
	my $hops = get_hops(11);
	my $t = time;
	$text = ' ' if !$text;
	return sprintf "PC11^%.1f^$dxcall^%s^%s^$text^$mycall^$main::mycall^$hops^~", $freq, cldate($t), ztime($t);
}

# create an announce message
sub pc12
{
	my ($call, $text, $tonode, $sysop, $wx) = @_;
	my $hops = get_hops(12);
	$sysop = ' ' if !$sysop;
	$text = ' ' if !$text;
	$wx = '0' if !$wx;
	$tonode = '*' if !$tonode;
	return "PC12^$call^$tonode^$text^$sysop^$main::mycall^$wx^$hops^~";
}

#
# add one or more users (I am expecting references that have 'call', 
# 'confmode' & 'here' method) 
#
# this will create a list of PC16 with up pc16_max_users in each
# called $self->pc16(..)
#
sub pc16
{
	my $self = shift;
	my @out;

	foreach (@_) {
		my $str = "PC16^$self->{call}";
		my $i;
    
		for ($i = 0; @_ > 0  && $i < $DXProt::pc16_max_users; $i++) {
			my $ref = shift;
			$str .= sprintf "^%s %s %d", $ref->call, $ref->confmode ? '*' : '-', $ref->here;
		}
		$str .= sprintf "^%s^", get_hops(16);
		push @out, $str;
	}
	return (@out);
}

# remove a local user
sub pc17
{
	my ($self, $ref) = @_;
	my $hops = get_hops(17);
	return "PC17^$ref->{call}^$self->{call}^$hops^";
}

# Request init string
sub pc18
{
	my $info = DXCluster::cluster;
	return "PC18^$info^$DXProt::myprot_version^~";
}

#
# add one or more nodes 
# 
sub pc19
{
	my $self = shift;
	my @out;

	while (@_) {
		my $str = "PC19";
		my $i;
    
		for ($i = 0; @_ && $i < $DXProt::pc19_max_nodes; $i++) {
			my $ref = shift;
			my $here = $ref->{here} ? '1' : '0';
			my $confmode = $ref->{confmode} ? '1' : '0';
			$str .= "^$here^$ref->{call}^$confmode^$ref->{pcversion}";
		}
		$str .= sprintf "^%s^", get_hops(19);
		push @out, $str;
	}
	return @out;
}

# end of Rinit phase
sub pc20
{
	return 'PC20^';
}

# delete a node
sub pc21
{
	my ($call, $reason) = @_;
	my $hops = get_hops(21);
	$reason = "Gone." if !$reason;
	return "PC21^$call^$reason^$hops^";
}

# end of init phase
sub pc22
{
	return 'PC22^';
}

# here status
sub pc24
{
	my $self = shift;
	my $call = $self->call;
	my $flag = $self->here ? '1' : '0';
	my $hops = get_hops(24);
  
	return "PC24^$call^$flag^$hops^";
}


# create a merged dx message (freq, dxcall, t, text, spotter, orig-node) 
sub pc26
{
	my ($freq, $dxcall, $t, $text, $spotter, $orignode) = @_;
	$text = ' ' unless $text;
	$orignode = $main::mycall unless $orignode;
	return sprintf "PC26^%.1f^$dxcall^%s^%s^$text^$spotter^$orignode^ ^~", $freq, cldate($t), ztime($t);
}

# create a merged WWV spot (logger, t, sfi, a, k, forecast, orig-node)
sub pc27
{
	my ($logger, $t, $sfi, $a, $k, $forecast, $orignode) = @_;
	return sprintf "PC27^%s^%-2.2s^$sfi^$a^$k^$forecast^$logger^$orignode^ ^~", cldate($t), ztime($t);
}

# message start (fromnode, tonode, to, from, t, private, subject, origin)
sub pc28
{
	my ($tonode, $fromnode, $to, $from, $t, $private, $subject, $origin, $rr) = @_;
	my $date = cldate($t);
	my $time = ztime($t);
	$private = $private ? '1' : '0';
	$rr = $rr ? '1' : '0';
	return "PC28^$tonode^$fromnode^$to^$from^$date^$time^$private^$subject^ ^5^$rr^ ^$origin^~";
}

# message text (from and to node same way round as pc29)
sub pc29 
{
	my ($fromnode, $tonode, $stream, $text) = @_;
	$text =~ s/\^/:/og;			# remove ^
	$text =~ s/\~/S/og;
	return "PC29^$fromnode^$tonode^$stream^$text^~";
}

# subject acknowledge (will have to and from node reversed to pc28)
sub pc30
{
	my ($fromnode, $tonode, $stream) = @_;
	return "PC30^$fromnode^$tonode^$stream^";
}

# acknowledge this tranche of lines (to and from nodes reversed to pc29 and pc28
sub pc31
{
	my ($fromnode, $tonode, $stream) = @_;
	return "PC31^$fromnode^$tonode^$stream^";
}

#  end of message from the sending end (pc28 node order)
sub pc32
{
	my ($fromnode, $tonode, $stream) = @_;
	return "PC32^$fromnode^$tonode^$stream^";
}

# acknowledge end of message from receiving end (opposite pc28 node order)
sub pc33
{
	my ($fromnode, $tonode, $stream) = @_;
	return "PC33^$fromnode^$tonode^$stream^";
}

# remote cmd send
sub pc34
{
	my($fromnode, $tonode, $msg) = @_;
	return "PC34^$tonode^$fromnode^$msg^~";
}

# remote cmd reply
sub pc35
{
	my($fromnode, $tonode, $msg) = @_;
	return "PC35^$tonode^$fromnode^$msg^~";
}

# send all the DX clusters I reckon are connected
sub pc38
{
	my @list = DXNode->get_all();
	my $list;
	my @nodes;
  
	foreach $list (@list) {
		push @nodes, $list->call;
	}
	return "PC38^" . join(',', @nodes) . "^~";
}

# tell the local node to discconnect
sub pc39
{
	my ($call, $reason) = @_;
	my $hops = get_hops(39);
	$reason = "Gone." if !$reason;
	return "PC39^$call^$reason^$hops^";
}

# cue up bulletin or file for transfer
sub pc40
{
	my ($to, $from, $fn, $bull) = @_;
	$bull = $bull ? '1' : '0';
	return "PC40^$to^$from^$fn^$bull^5^";
}

# user info
sub pc41
{
	my ($call, $sort, $info) = @_;
	my $hops = get_hops(41);
	$sort = $sort ? "$sort" : '0';
	return "PC41^$call^$sort^$info^$hops^~";
}

# abort message
sub pc42
{
	my ($fromnode, $tonode, $stream) = @_;
	return "PC42^$fromnode^$tonode^$stream^";
}

# bull delete
sub pc49
{
	my ($from, $subject) = @_;
	my $hops = get_hops(49);
	return "PC49^$from^$subject^$hops^~";
}

# periodic update of users, plus keep link alive device (always H99)
sub pc50
{
	my $me = DXCluster->get_exact($main::mycall);
	my $n = $me->users ? $me->users : '0';
	return "PC50^$main::mycall^$n^H99^";
}

# generate pings
sub pc51
{
	my ($to, $from, $val) = @_;
	return "PC51^$to^$from^$val^";
}
1;
__END__
