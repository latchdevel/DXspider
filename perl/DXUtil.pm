#
# various utilities which are exported globally
#
# Copyright (c) 1998 - Dirk Koopman G1TLH
#
# $Id$
#

package DXUtil;

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(atime ztime cldate
            );

@month = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);

# a full time for logging and other purposes
sub atime
{
  my $t = shift;
  my ($sec,$min,$hour,$mday,$mon,$year) = gmtime((defined $t) ? $t : time);
  $year += 1900;
  my $buf = sprintf "%02d%s%04d\@%02d:%02d:%02d", $mday, $month[$mon], $year, $hour, $min, $sec;
  return $buf;
}

# get a zulu time in cluster format (2300Z)
sub ztime
{
  my $t = shift;
  my ($sec,$min,$hour) = gmtime((defined $t) ? $t : time);
  $year += 1900;
  my $buf = sprintf "%02d%02dZ", $hour, $min;
  return $buf;

}

# get a cluster format date (23-Jun-1998)
sub cldate
{
  my $t = shift;
  my ($sec,$min,$hour,$mday,$mon,$year) = gmtime((defined $t) ? $t : time);
  $year += 1900;
  my $buf = sprintf "%02d-%s-%04d", $mday, $month[$mon], $year;
  return $buf;
}


