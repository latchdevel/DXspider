#!/usr/bin/perl
# 
# The geomagnetic information and calculation module
# a chanfe
#
# Copyright (c) 1998 - Dirk Koopman G1TLH
#
# $Id$
#

package Geomag;

use DXVars;
use DXUtil;
use DXLog;
use Julian;
use FileHandle;
use Carp;

use strict;
use vars qw($date $sfi $k $a $forecast @allowed @denied $fp $node $from);

$fp = 0;            # the DXLog fcb
$date = 0;          # the unix time of the WWV (notional)
$sfi = 0;           # the current SFI value
$k = 0;             # the current K value
$a = 0;             # the current A value
$forecast = "";     # the current geomagnetic forecast
$node = "";         # originating node
$from = "";         # who this came from
@allowed = ();      # if present only these callsigns are regarded as valid WWV updators
@denied = ();       # if present ignore any wwv from these callsigns
my $dirprefix = "$main::data/wwv";
my $param = "$dirprefix/param";

sub init
{
	$fp = DXLog::new('wwv', 'dat', 'm');
	mkdir $dirprefix, 0777 if !-e $dirprefix;        # now unnecessary DXLog will create it
	do "$param" if -e "$param";
	confess $@ if $@;
}

# write the current data away
sub store
{
  my $fh = new FileHandle;
  open $fh, "> $param" or confess "can't open $param $!";
  print $fh "# Geomagnetic data parameter file last mod:", scalar gmtime, "\n";
  print $fh "\$date = $date;\n";
  print $fh "\$sfi = $sfi;\n";
  print $fh "\$a = $a;\n";
  print $fh "\$k = $k;\n";
  print $fh "\$from = '$from';\n";
  print $fh "\$node = '$node';\n";
  print $fh "\@denied = qw(", join(' ', @denied), ");\n" if @denied > 0;
  print $fh "\@allowed = qw(", join(' ', @allowed), ");\n" if @allowed > 0;
  close $fh;

  # log it
  $fp->writeunix($date, "$from^$date^$sfi^$a^$k^$forecast^$node");
}

# update WWV info in one go (usually from a PC23)
sub update
{
  my ($mydate, $mytime, $mysfi, $mya, $myk, $myforecast, $myfrom, $mynode) = @_;
  if ((@allowed && grep {$_ eq $from} @allowed) || 
      (@denied && !grep {$_ eq $from} @denied) ||
	  (@allowed == 0 && @denied == 0)) {
	  
	my $trydate = cltounix($mydate, sprintf("%02d18Z", $mytime));
	if ($trydate >= $date) {
      $sfi = 0 + $mysfi;
      $k = 0 + $myk;
      $a = 0 + $mya;
      $forecast = $myforecast;
	  $date = $trydate;
	  $from = $myfrom;
	  $node = $mynode;
	  
	  store();
	}
  }
}

# add or substract an allowed callsign
sub allowed
{
  my $flag = shift;
  if ($flag eq '+') {
    push @allowed, map {uc $_} @_;
  } else {
    my $c;
    foreach $c (@_) {
	  @allowed = map {$_ ne uc $c} @allowed; 
	} 
  }
  store();
}

# add or substract a denied callsign
sub denied
{
  my $flag = shift;
  if ($flag eq '+') {
    push @denied, map {uc $_} @_;
  } else {
    my $c;
    foreach $c (@_) {
	  @denied = map {$_ ne uc $c} @denied; 
	} 
  }
  store();
}

# accessor routines (when I work how symbolic refs work I might use one of those!)
sub sfi
{
  @_ ? $sfi = shift : $sfi ;
}

sub k
{
  @_ ? $k = shift : $k ;
}

sub a
{
  @_ ? $a = shift : $a ;
}

sub forecast
{
  @_ ? $forecast = shift : $forecast ;
}

#
# print some items from the log backwards in time
#
# This command outputs a list of n lines starting from line $from to $to
#
sub print
{
	my $from = shift;
	my $to = shift;
	my @date = $fp->unixtoj(shift);
	my $pattern = shift;
	my $search;
	my @out;
	my $eval;
	my $count;
	    
	$search = 1;
	$eval = qq(
			   my \$c;
			   my \$ref;
			   for (\$c = \$#in; \$c >= 0; \$c--) {
					\$ref = \$in[\$c];
					if ($search) {
						\$count++;
						next if \$count < \$from;
						push \@out, print_item(\$ref);
						last LOOP if \$count >= \$to;                  # stop after n
					}
				}
			  );
	
	$fp->close;                                      # close any open files

	my $fh = $fp->open(@date); 
LOOP:
	while ($count < $to) {
		my @in = ();
		if ($fh) {
			while (<$fh>) {
				chomp;
				push @in, [ split '\^' ] if length > 2;
			}
			eval $eval;               # do the search on this file
			return ("Spot search error", $@) if $@;
		}
		$fh = $fp->openprev();      # get the next file
		last if !$fh;
	}

	return @out;
}

#
# the standard log printing interpreting routine.
#
# every line that is printed should call this routine to be actually visualised
#
# Don't really know whether this is the correct place to put this stuff, but where
# else is correct?
#
# I get a reference to an array of items
#
sub print_item
{
	my $r = shift;
	my @ref = @$r;
	my $d = cldate($ref[1]);
	my ($t) = (gmtime($ref[1]))[2];

	return sprintf("$d   %02d %5d %3d %3d %-37s <%s>", $t, $ref[2], $ref[3], $ref[4], $ref[5], $ref[0]);
}

#
# read in this month's data
#
sub readfile
{
	my @date = $fp->unixtoj(shift);
	my $fh = $fp->open(@date); 
	my @spots = ();
	my @in;
	
	if ($fh) {
		while (<$fh>) {
			chomp;
			push @in, [ split '\^' ] if length > 2;
		}
	}
	return @in;
}
1;
__END__;
