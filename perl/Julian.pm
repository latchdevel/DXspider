#
# various julian date calculations
#
# Copyright (c) - 1998 Dirk Koopman G1TLH
#
# $Id$
#

package Julian;

use FileHandle;
use DXDebug;
use Carp;

use strict;

my @days = (31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31);

# take a unix date and transform it into a julian day (ie (1998, 13) = 13th day of 1998)
sub unixtoj
{
  my ($t) = @_;
  my ($day, $mon, $year) = (gmtime($t))[3..5];
  my $jday;
  
  # set the correct no of days for february
  if ($year < 100) {
    $year += ($year < 50) ? 2000 : 1900;
  }
  $days[1] = isleap($year) ? 29 : 28;
  for (my $i = 0, $jday = 0; $i < $mon; $i++) {
    $jday += $days[$i];
  }
  $jday += $day;
  return ($year, $jday);
}

# take a julian date and subtract a number of days from it, returning the julian date
sub sub
{
  my ($year, $day, $amount) = @_;
  my $diny = isleap($year) ? 366 : 365;
  $day -= $amount;
  while ($day <= 0) {
    $day += $diny;
	$year -= 1;
	$diny = isleap($year) ? 366 : 365;
  }
  return ($year, $day);
}

sub add
{
  my ($year, $day, $amount) = @_;
  my $diny = isleap($year) ? 366 : 365;
  $day += $amount;
  while ($day > $diny) {
    $day -= $diny;
	$year += 1;
	$diny = isleap($year) ? 366 : 365;
  }
  return ($year, $day);
} 

sub cmp
{
  my ($y1, $d1, $y2, $d2) = @_;
  return $d1 - $d2 if ($y1 == $y2);
  return $y1 - $y2;
}

# is it a leap year?
sub isleap
{
  my $year = shift;
  return ($year % 4 == 0 && ($year % 100 != 0 || $year % 400 == 0)) ? 1 : 0; 
}

# this section deals with files that are julian date based

# open a data file with prefix $fn/$year/$day.dat and return an object to it
sub open
{
  my ($pkg, $fn, $year, $day, $mode) = @_;

  # if we are writing, check that the directory exists
  if (defined $mode) {
    my $dir = "$fn/$year";
	mkdir($dir, 0777) if ! -e $dir;
  }
  my $self = {};
  $self->{fn} = sprintf "$fn/$year/%03d.dat", $day;
  $mode = 'r' if !$mode;
  my $fh = new FileHandle $self->{fn}, $mode;
  return undef if !$fh;
  $fh->autoflush(1) if $mode ne 'r';         # make it autoflushing if writable
  $self->{fh} = $fh;
  $self->{year} = $year;
  $self->{day} = $day;
  dbg("julian", "opening $self->{fn}\n");
  
  return bless $self, $pkg;
}

# close the data file
sub close
{
  my $self = shift;
  undef $self->{fh};      # close the filehandle
  delete $self->{fh};
}

sub DESTROY               # catch undefs and do what is required further do the tree
{
  my $self = shift;
  dbg("julian", "closing $self->{fn}\n");
  undef $self->{fh} if defined $self->{fh};
} 

1;
