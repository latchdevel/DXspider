#
# This package simply takes a string, looks it up in a
# hash and returns the value.
#
# The hash is produced by reading the Alias file in both command directories
# which contain entries for the %cmd hash. This file is in different forms in 
# the two directories:-
#
# in the main cmd directory it has entries like:-
#
# package CmdAlias;
#
# %alias = (
#   sp => 'send private',
#   s/p => 'send private', 
#   sb => 'send bulletin', 
# );
#
# for the local cmd directory you should do it like this:-
#
# package CmdAlias;
#
# $alias{'s/p'} = 'send private';
# $alias{'s/b'} = 'send bulletin';
#
# This will allow you to override as well as add to the basic set of commands 
#
# This system works in same way as the commands, if the modification times of
# the two files have changed then they are re-read.
#
# Copyright (c) 1998 Dirk Koopman G1TLH
#
# $Id$
#

package CmdAlias;

use DXVars;
use DXDebug;
use Carp;

use strict;

use vars qw(%alias $fn $localfn);

%alias = ();

$fn = "$main::cmd/Aliases";
$localfn = "$main::localcmd/Aliases";

sub load
{
	my $ref = shift;
	if (-e $localfn) {
		do $localfn;
		return ($@) if $@ && ref $ref;
		confess $@ if $@;
		return ();
	}
	do $fn;
	return ($@) if $@ && ref $ref;
	confess $@ if $@;
	return ();
}

sub init
{
	load();
}

#
# called as CmdAlias::get_cmd("string");
#
sub get_cmd
{
  my $s = shift;
  my ($let) = unpack "A1", $s;
  my ($i, $n, $ref);

  $let = lc $let;
  
  $ref = $alias{$let};
  return undef if !$ref;
  
  $n = @{$ref};
  for ($i = 0; $i < $n; $i += 3) {
    if ($s =~ /$ref->[$i]/i) {
 	  my $ri = qq{\$ro = "$ref->[$i+1]"};
	  my $ro;
	  eval $ri;
	  return $ro;
	}
  }
  return undef;
}

#
# called as CmdAlias::get_hlp("string");
#
sub get_hlp
{
  my $s = shift;
  my ($let) = unpack "A1", $s;
  my ($i, $n, $ref);

  $let = lc $let;
  
  $ref = $alias{$let};
  return undef if !$ref;
  
  $n = @{$ref};
  for ($i = 0; $i < $n; $i += 3) {
    if ($s =~ /$ref->[$i]/i) {
 	  my $ri = qq{\$ro = "$ref->[$i+2]"};
	  my $ro;
	  eval $ri;
	  return $ro;
	}
  }
  return undef;
}


