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
@EXPORT = qw(atime ztime cldate cldatetime slat slong yesno promptf
             print_all_fields
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

# return a cluster style date time
sub cldatetime
{
  my $t = shift;
  my $date = cldate($t);
  my $time = ztime($t);
  return "$date $time";
}

# turn a latitude in degrees into a string
sub slat
{
  my $n = shift;
  my ($deg, $min, $let);
  $let = $n >= 0 ? 'N' : 'S';
  $n = abs $n;
  $deg = int $n;
  $min = int (($n - $deg) * 60);
  return "$deg $min $let";
}

# turn a longitude in degrees into a string
sub slong
{
  my $n = shift;
  my ($deg, $min, $let);
  $let = $n >= 0 ? 'E' : 'W';
  $n = abs $n;
  $deg = int $n;
  $min = int (($n - $deg) * 60);
  return "$deg $min $let";
}

# turn a true into 'yes' and false into 'no'
sub yesno
{
  my $n = shift;
  return $n ? $main::yes : $main::no;
}

# format a prompt with its current value and return it with its privilege
sub promptf
{
  my ($line, $value) = @_;
  my ($priv, $prompt, $action) = split ',', $line;

  # if there is an action treat it as a subroutine and replace $value
  if ($action) {
    my $q = qq{\$value = $action(\$value)};
	eval $q;
  }
  $prompt = sprintf "%15s: %s", $prompt, $value;
  return ($priv, $prompt);
}

# print all the fields for a record according to privilege
#
# The prompt record is of the format '<priv>,<prompt>[,<action>'
# and is expanded by promptf above
#
sub print_all_fields
{
  my $self = shift;    # is a dxchan
  my $ref = shift;     # is a thingy with field_prompt and fields methods defined
  my @out = @_;
 
  my @fields = $ref->fields;
  my $field;
  my @out;

  foreach $field (sort @fields) {
    my ($priv, $ans) = promptf($ref->field_prompt($field), $ref->{$field});
    push @out, $ans if ($self->priv >= $priv);
  }
  return @out;
}
