#
# prefix handling
#
# Copyright (c) - Dirk Koopman G1TLH
#
# $Id$
#

package Prefix;

use Carp;
use DXVars;
use DB_File;

use strict;

my $db;     # the DB_File handle
my %prefix_loc;   # the meat of the info
my %prefix;       # the prefix list

sub load
{
  if ($db) {
    untie %prefix;
	%prefix = ();
	%prefix_loc = ();
  }
  $db = tie(%prefix, "DB_File", undef, O_RDWR|O_CREAT, 0, $DB_BTREE) or confess "can't tie %prefix ($!)";  
  do "$main::data/prefix_data.pl";
  confess $@ if $@;
}

sub store
{
  my ($k, $l);
  my $fh = new FileHandle;
  my $fn = "$main::data/prefix_data.pl";
  
  confess "Prefix system not started" if !$db;
  
  # save versions!
  rename "$fn.oooo", "$fn.ooooo" if -e "$fn.oooo";
  rename "$fn.ooo", "$fn.oooo" if -e "$fn.ooo";
  rename "$fn.oo", "$fn.ooo" if -e "$fn.oo";
  rename "$fn.o", "$fn.oo" if -e "$fn.o";
  rename "$fn", "$fn.o" if -e "$fn";
  
  $fh->open(">$fn") or die "Can't open $fn ($!)";

  # prefix location data
  $fh->print("%prefix_loc = (\n");
  foreach $l (sort {$a <=> $b} keys %prefix_loc) {
    my $r = $prefix_loc{$l};
	$fh->printf("   $l => { name => '%s', dxcc => %d, itu => %d, utcoff => %d, lat => %f, long => %f },\n",
	            $r->{name}, $r->{dxcc}, $r->{itu}, $r->{cq}, $r->{utcoff}, $r->{lat}, $r->{long});
  }
  $fh->print(");\n\n");

  # prefix data
  $fh->print("%prefix = (\n");
  foreach $k (sort keys %prefix) {
    $fh->print("   '$k' => [");
	my @list = @{$prefix{$k}};
	my $l;
	my $str;
	foreach $l (@list) {
      $str .= " $l,";
    }
	chop $str;  
	$fh->print("$str ],\n");
  }
  $fh->print(");\n");
  $fh->close;
}

# this may return several entries, be warned!
#
# what you get is a list of pairs of:-
# 
# prefix => \[ @list of references to prefix_locs ]
#
# This routine will only do what you ask for, if you wish to be intelligent
# then that is YOUR problem!
#
sub get
{
  
}

1;

__END__
