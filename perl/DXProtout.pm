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

use strict;

#
# All the PCxx generation routines
#

# create a talk string (called $self->pc10(...)
sub pc10
{
  my ($self, $to, $via, $text) = @_;
  my $user2 = $via ? $to : ' ';
  my $user1 = $via ? $via : $to;
  my $mycall = $self->call;
  $text = unpad($text);
  $text = ' ' if !$text;
  return "PC10^$mycall^$user1^$text^*^$user2^$main::mycall^~";  
}

# create a dx message (called $self->pc11(...)
sub pc11
{
  my ($self, $freq, $dxcall, $text) = @_;
  my $mycall = $self->call;
  my $hops = get_hops(11);
  my $t = time;
  $text = ' ' if !$text;
  return sprintf "PC11^%.1f^$dxcall^%s^%s^$text^$mycall^$hops^~", $freq, cldate($t), ztime($t);
}

# create an announce message
sub pc12
{
  my ($self, $text, $tonode, $sysop, $wx) = @_;
  my $hops = get_hops(12);
  $sysop = $sysop ? '*' : ' ';
  $text = ' ' if !$text;
  $wx = '0' if !$wx;
  $tonode = '*' if !$tonode;
  return "PC12^$self->{call}^$tonode^$text^$sysop^$main::mycall^$wx^$hops^~";
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
  return "PC17^$self->{call}^$ref->{call}^$hops^";
}

# Request init string
sub pc18
{
  return "PC18^wot a load of twaddle^$DXProt::myprot_version^~";
}

#
# add one or more nodes 
# 
sub pc19
{
  my $self = shift;
  my @out;

  while (@_) {
    my $str = "PC19^$self->{call}";
    my $i;
    
    for ($i = 0; @_ && $i < $DXProt::pc19_max_nodes; $i++) {
      my $ref = shift;
      $str .= "^$ref->{here}^$ref->{call}^$ref->{confmode}^$ref->{pcversion}";
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
  my ($ref, $reason) = @_;
  my $call = $ref->call;
  my $hops = get_hops(21);
  $reason = "Gone." if !$reason;
  return "PC21^$call^$reason^$hops^";
}

# end of init phase
sub pc22
{
  return 'PC22^';
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

# periodic update of users, plus keep link alive device (always H99)
sub pc50
{
  my $n = DXNodeuser->count;
  return "PC50^$main::mycall^$n^H99^";
}

# generate pings
sub pc51
{
  my ($self, $to, $from, $val) = @_;
  return "PC51^$to^$from^$val^";
}
1;
__END__
