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

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(msg);

%msgs = (
  l1 => 'Sorry $_[0], you are already logged on on another channel',
  l2 => 'Hello $_[0], this is $main::mycall located in $main::myqth',
);

sub msg
{
  my $self = shift;
  my $s = $msgs{$self};
  return "unknown message '$self'" if !defined $s;

  return eval '"'. $s . '"';
}
  
