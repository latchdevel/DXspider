#!/usr/bin/perl
#
# Analyse the dxcc info in the prefix database, listing the 'official' country and its number
# and also looking for duplicates and missing numbers
#
#

use Prefix;


Prefix::load();

sub comp
{
  my ($a, $b) = @_;
  return ($a->dxcc()-0) <=> ($b->dxcc()-0);
}

$lastdxcc = 0;
foreach $ref (sort {$a->dxcc() <=> $b->dxcc()} values %Prefix::prefix_loc) {
  $name = $ref->name();
  $dxcc = $ref->dxcc();
  while ($lastdxcc < $dxcc - 1) {
	++$lastdxcc;
    print "dxcc: $lastdxcc name:  ** MISSING\n";
  }
  $dup = "";
  $dup = "** DUPLICATE" if $dxcc == $lastdxcc;
  print "dxcc: $dxcc name: $name $dup\n";
  $lastdxcc = $dxcc;
}
