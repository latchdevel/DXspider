#!/usr/bin/perl
# a program to create a prefix file from a wpxloc.raw file
#
# Copyright (c) - Dirk Koopman G1TLH
#
# $Id$
#

require 5.004;

# search local then perl directories
BEGIN {
	# root of directory tree for this system
	$root = "/spider"; 
	$root = $ENV{'DXSPIDER_ROOT'} if $ENV{'DXSPIDER_ROOT'};
	
	unshift @INC, "$root/perl";	# this IS the right way round!
	unshift @INC, "$root/local";
}

use DXVars;
use Data::Dumper;

%loc = ();        # the location unique hash
$nextloc = 1;     # the next location number
%locn = ();       # the inverse of the above
%pre = ();        # the prefix hash
%pren = ();       # the inverse

# open the input file
$ifn = $ARGV[0] if $ARGV[0];
$ifn = "$data/wpxloc.raw" if !$fn;
open (IN, $ifn) or die "can't open $ifn ($!)";

# first pass, find all the 'master' location records
while (<IN>) {
  next if /^\!/;    # ignore comment lines
  chomp;
  @f  = split;       # get each 'word'
  next if @f == 0;   # ignore blank lines

  if ($f[14] eq '@' || $f[15] eq '@') {
    $locstr = join ' ', @f[1..13];
    $loc = $loc{$locstr};
    $loc = addloc($locstr) if !$loc;
  }
}

#foreach $loc (sort {$a <=> $b;} keys %locn) {
#  print "loc: $loc data: $locn{$loc}\n";
#}

# go back to the beginning and this time add prefixes (adding new location entries, if required)
seek(IN, 0, 0);

while (<IN>) {
  $line++;
  next if /^\!/;    # ignore comment lines
  chomp;
  @f  = split;       # get each 'word'
  next if @f == 0;   # ignore blank lines
  
  # location record
  $locstr = join ' ', @f[1..13];
  $loc = $loc{$locstr};
  $loc = addloc($locstr) if !$loc;
  
  @prefixes = split /,/, $f[0];
  foreach $p (@prefixes) {
    my $ref;
	
	if ($p =~ /#/) {
	  my $i;
	  for ($i = 0; $i < 9; ++$i) {
	    my $t = $p;
		$t =~ s/#/$i/;
		addpre($t, $loc);
	  }
	} else {
	  addpre($p, $loc);
    }	
  }
}

close(IN);

#print Data::Dumper->Dump([\%pre, \%locn], [qw(pre locn)]);

# now open the rsgb.cty file and process that again the prefix file we have
open(IN, "$data/rsgb.cty") or die "Can't open $data/rsgb.cty ($!)";
while (<IN>) {
  chomp;
  @f = split /:\s+|;/;
  my $p = uc $f[4];
  my $ref = $pre{$p};
  if ($ref) {
    # split up the alias string
	my @alias = split /=/, $f[5];
	my $a;
	foreach $a (@alias) {
	  next if $a eq $p;  # ignore if we have it already
	  my $nref = $pre{$a};
	  $pre{$a} = $ref if !$nref;       # copy the original ref if new 
	}
  } else {
    print "unknown prefix $p\n";
  }
}

open(OUT, ">$data/prefix_data.pl") or die "Can't open $data/prefix_data.pl ($!)";

print OUT "\%pre = (\n";
foreach $k (sort keys %pre) {
  my $ans = printpre($k);
  print OUT "  '$k' => '$ans',\n";
}
print OUT ");\n\n";

print OUT "\n\%prefix_loc = (\n";
foreach $l (sort {$a <=> $b} keys %locn) {
  print OUT "   $l => bless( {";
  my ($name, $dxcc, $itu, $cq, $utcoff, $latd, $latm, $lats, $latl, $longd, $longm, $longs, $longl) = split /\s+/, $locn{$l};
  
  $longd += ($longm/60);
  $longd = 0-$longd if (uc $longl) eq 'W'; 
  $latd += ($latm/60);
  $latd = 0-$latd if (uc $latl) eq 'S';
  print OUT " name => '$name',";
  print OUT " dxcc => $dxcc,";
  print OUT " itu => $itu,";
  print OUT " cq => $cq,";
  print OUT " utcoff => $utcoff,";
  print OUT " lat => $latd,";
  print OUT " long => $longd";
  print OUT " }, 'Prefix'),\n";
}
print OUT ");\n\n";

close(OUT);

sub addpre
{
  my ($p, $ent) = @_;
  my $ref = $pre{$p};
  $ref = $pre{$p} = [] if !$ref;
  push @{$ref}, $ent;;
}

sub printpre
{
  my $p = shift;
  my $ref = $pre{$p};
  my $out;
  my $r;
  
  foreach $r (@{$ref}) {
    $out .= "$r,";
  }
  chop $out;
  return $out;
}

sub addloc
{
  my $locstr = shift;
  $locstr =~ s/\'/\\'/g;
  my $loc = $loc{$locstr} = $nextloc++;
  $locn{$loc} = $locstr;
  return $loc;
}
