#
# DX cluster message strings for output
#
# Each message string will substitute $_[x] positionally. What this means is
# that if you don't like the order in which fields in each message is output then 
# you can change it. Also you can include various globally accessible variables
# in the string if you want. 
#
# Largely because I don't particularly want to have to change all these messages
# in every upgrade I shall attempt to add new field to the END of the list :-)
#
# Copyright (c) 1998 - Dirk Koopman G1TLH
#
# $Id$
#

package DXM;

use DXVars;

%msgs = (
  addr => 'Address set to: $_[0]',
  anns => 'Announce flag set on $_[0]',
  annu => 'Announce flag unset on $_[0]',
  conother => 'Sorry $_[0] you are connected on another port',
  concluster => 'Sorry $_[0] you are already connected elsewhere on the cluster',
  dxs => 'DX Spots flag set on $_[0]',
  dxu => 'DX Spots flag unset on $_[0]',
  e1 => 'Invalid command',
  e2 => 'Error: $_[0]',
  e3 => '$_[0]: $_[1] not found',
  e4 => 'Need at least a prefix or callsign',
  e5 => 'Not Allowed',
  email => 'E-mail address set to: $_[0]',
  heres => 'Here set on $_[0]',
  hereu => 'Here unset on $_[0]',
  homebbs => 'Home BBS set to: $_[0]',
  homenode => 'Home Node set to: $_[0]',
  l1 => 'Sorry $_[0], you are already logged on on another channel',
  l2 => 'Hello $_[0], this is $main::mycall located in $main::myqth',
  m2 => '$_[0] Information: $_[1]',
  node => '$_[0] set as AK1A style Node',
  nodee1 => 'You cannot use this command whilst your target ($_[0]) is on-line',
  pr => '$_[0] de $main::mycall $main::cldate $main::ztime >',
  priv => 'Privilege level changed on $_[0]',
  prx => '$main::$mycall >',
  talks => 'Talk flag set on $_[0]',
  talku => 'Talk flag unset on $_[0]',
  wwvs => 'WWV flag set on $_[0]',
  wwvu => 'WWV flag unset on $_[0]',
);

sub msg
{
  my $self = shift;
  my $s = $msgs{$self};
  return "unknown message '$self'" if !defined $s;
  my $ans = eval qq{ "$s" };
  confess $@ if $@;
  return $ans;
}
  
