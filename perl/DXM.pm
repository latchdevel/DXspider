#
# DX cluster message strings for output
#
# Copyright (c) 1998 - Dirk Koopman G1TLH
#
# $Id$
#

package DXM;

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(m);

%msgs = (
  l1 => "Sorry $a[0], you are already logged on on another channel",
  l2 => "Hello $a[0], this is $a[1] located in $a[2]",
);

sub m
{
  my $self = shift;
  local @a = @_;
  my $s = $msg{$self};
  return "unknown message '$self'" if !defined $s;
  return eval $s;
}
  
