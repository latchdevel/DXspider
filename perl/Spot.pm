#
# the dx spot handler
#
# Copyright (c) - 1998 Dirk Koopman G1TLH
#
# $Id$
#

package Spot;

use FileHandle;
use DXVars;
use DXDebug;
use Julian;
use Prefix;
use Carp;

@ISA = qw(Julian);

use strict;

my $fp;
my $maxspots = 50;      # maximum spots to return
my $defaultspots = 10;    # normal number of spots to return
my $maxdays = 35;        # normal maximum no of days to go back
my $dirprefix = "$main::data/spots";

sub prefix
{
  return $dirprefix;
}

# add a spot to the data file (call as Spot::add)
sub add
{
  my @spot = @_;    # $freq, $call, $t, $comment, $spotter = @_

  # sure that the numeric things are numeric now (saves time later)
  $spot[0] = 0 + $spot[0];
  $spot[2] = 0 + $spot[2];
  
  # remove ssid if present on spotter
  $spot[4] =~ s/-\d+$//o;

  # compare dates to see whether need to open another save file (remember, redefining $fp 
  # automagically closes the output file (if any))
  my @date = Julian::unixtoj($spot[2]);
  $fp = Spot->open(@date, ">>") if (!$fp || Julian::cmp(@date, $fp->{year}, $fp->{day}));

  # save it
  my $fh = $fp->{fh};

  # add the 'dxcc' country on the end
  my @dxcc = Prefix::extract($spot[1]);
  push @spot, (@dxcc > 0 ) ? $dxcc[1]->dxcc() : 0;

  $fh->print(join("\^", @spot), "\n");
}

# search the spot database for records based on the field no and an expression
# this returns a set of references to the spots
#
# the expression is a legal perl 'if' statement with the possible fields indicated
# by $f<n> where :-
#
#   $f0 = frequency
#   $f1 = call
#   $f2 = date in unix format
#   $f3 = comment
#   $f4 = spotter
#   $f5 = dxcc country
#
# In addition you can specify a range of days, this means that it will start searching
# from <n> days less than today to <m> days less than today
#
# Also you can select a range of entries so normally you would get the 0th (latest) entry
# back to the 5th latest, you can specify a range from the <x>th to the <y>the oldest.
#
# This routine is designed to be called as Spot::search(..)
#

sub search
{
  my ($expr, $dayfrom, $dayto, $from, $to) = @_;
  my $eval;
  my @out;
  my $ref;
  my $i;
  my $count;
  my @today = Julian::unixtoj(time);
  my @fromdate;
  my @todate;
  
  if ($dayfrom > 0) {
    @fromdate = Julian::sub(@today, $dayfrom);
  } else {
    @fromdate = @today;
	$dayfrom = 0;
  }
  if ($dayto > 0) {
    @todate = Julian::sub(@fromdate, $dayto);
  } else {
    @todate = Julian::sub(@fromdate, $maxdays);
  }
  if ($from || $to) {
    $to = $from + $maxspots if $to - $from > $maxspots || $to - $from <= 0;
  } else {
    $from = 0;
	$to = $defaultspots;
  }

  $expr =~ s/\$f(\d)/\$ref->[$1]/g;               # swap the letter n for the correct field name
  
  dbg("search", "expr='$expr', spotno=$from-$to, day=$dayfrom-$dayto\n");
  
  # build up eval to execute
  $eval = qq(my \$c;
    for (\$c = \$#spots; \$c >= 0; \$c--) {
	  \$ref = \$spots[\$c];
	  if ($expr) {
	    \$count++;
		next if \$count < \$from;                  # wait until from 
        push(\@out, \$ref);
		last LOOP if \$count >= \$to;                  # stop after to
	  }
  });

LOOP:
  for ($i = 0; $i < 60; ++$i) {
    my @now = Julian::sub(@fromdate, $i);
	last if Julian::cmp(@now, @todate) <= 0;         
	
	my @spots = ();
	my $fp = Spot->open(@now);  # get the next file
	if ($fp) {
	  my $fh = $fp->{fh};
	  my $in;
	  foreach $in (<$fh>) {
	    chomp $in;
        push @spots, [ split('\^', $in) ];
	  }
	  my $ref;
	  eval $eval;               # do the search on this file
	  return ("error", $@) if $@;
	}
  }

  return @out;
}

# open a spot file of the Julian day
sub open
{
  my $pkg = shift;
  return Julian::open("spot", $dirprefix, @_);
}

# close a spot file
sub close
{
  # do nothing, unreferencing or overwriting the $self will close it  
}

1;
