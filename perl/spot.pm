#
# the dx spot handler
#
# Copyright (c) - 1998 Dirk Koopman G1TLH
#
# $Id$
#

package spot;

use FileHandle;
use DXVars;
use DXDebug;
use julian;

@ISA = qw(julian);

use strict;

my $fp;
my $maxdays = 60;    # maximum no of days to store spots in the table
my $prefix = "$main::data/spots";
my @table = ();      # the list of spots (held in reverse order)

# read in n days worth of dx spots into memory
sub init
{
  my @today = julian->unixtoj(time);        # get the julian date now
  my @first = julian->sub(@today, $maxdays);     # get the date $maxdays ago
  my $count;
  
  mkdir($prefix, 0777) if ! -e $prefix;     # create the base directory if required
  for (my $i = 0; $i < $maxdays; ++$i) {
    my $ref = spot->open(@first);
	if ($ref) {
	  my $fh = $ref->{fh};
	  while (<$fh>) {
	    chomp;
	    my @ent = split /\^/;
	    unshift @spot::table, [ @ent ];                # stick this ref to anon list on the FRONT of the table
		++$count;
	  }
	}
    @first = julian->add(@first, 1);
  }
  return $count;
}

# create a new spot on the front of the list, add it to the data file
sub new
{
  my $pkg = shift;
  my @spot = @_;    # $freq, $call, $t, $comment, $spotter = @_

  # sure that the numeric things are numeric now (saves time later)
  $spot[0] = 0 + $spot[0];
  $spot[2] = 0 + $spot[2];
  
  # save it on the front of the list
  unshift @spot::table, [ @spot ];
  
  # compare dates to see whether need to open a other save file
  my @date = julian->unixtoj($spot[2]);
  $fp = spot->open(@date, ">>") if (!$fp || julian->cmp(@date, $fp->{year}, $fp->{day}));
  my $fh = $fp->{fh};
  $fh->print(join("\^", @spot), "\n");
}

# purge all the spots older than $maxdays - this is fairly approximate
# this should be done periodically from some cron task
sub purge
{
  my $old = time - ($maxdays * 86400);
  my $ref;
  
  while (@spot::table) {
    my $ref = pop @spot::table;
	if (${$ref}[2] > $old) {
	  push @spot::table, $ref;        # put it back
	  last;                     # and leave
	}
  }
}

# search the spot database for records based on the field no and an expression
# this returns a set of references to the spots
#
# for string fields supply a pattern to match
# for numeric fields supply a range of the format 'n > x  && n < y' (the n will
# changed to the correct field name) [ n is literally the letter 'n' ]
#
sub search
{
  my ($pkg, $field, $expr) = @_;
  my $eval;
  my @out;
  my $ref;
 
  dbg('spot', "input expr = $expr\n");
  if ($field == 0 || $field == 2) {              # numeric fields
    $expr =~ s/n/\$ref->[$field]/g;               # swap the letter n for the correct field name
  } else {
    $expr = qq(\$ref->[$field] =~ /$expr/oi);      # alpha expressions
  }
  dbg('spot', "expr now = $expr\n");
  
  # build up eval to execute
  $eval = qq(foreach \$ref (\@spot::table) {
    push \@out, \$ref if $expr;
  });
  dbg('spot', "eval = $eval\n");
  eval $eval;                                   # execute it
  return @out;
}

# open a spot file of the julian day
sub open
{
  my $pkg = shift;
  return julian->open("spot", $prefix, @_);
}

# close a spot file
sub close
{
  # do nothing, unreferencing or overwriting the $self will close it  
}

1;
