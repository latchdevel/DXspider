#!/usr/bin/perl
#
# convert an Ak1a DX.DAT file to comma delimited form
#
#

use Prefix;


Prefix::load();

sub comp
{
  my ($a, $b) = @_;
  return ($a->dxcc()-0) <=> ($b->dxcc()-0);
}

foreach $ref (sort {$a->dxcc() <=> $b->dxcc()} values %Prefix::prefix_loc) {
  $name = $ref->name();
  $dxcc = $ref->dxcc();
  print "dxcc: $dxcc name: $name\n";
}
