#
# various utilities which are exported globally
#

package DXUtil;

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(atime
            );

@month = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);

sub atime
{
  my ($sec,$min,$hour,$mday,$mon,$year) = gmtime(time);
  $year += 1900;
  my $buf = sprintf "%02d%s%04d\@%02d:%02d:%02d", $mday, $month[$mon], $year, $hour, $min, $sec;
  return $buf;
}



