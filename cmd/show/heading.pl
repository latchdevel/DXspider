#
# show the dxcc number for each callsign or prefix entered
#
# $Id$
#

my ($self, $line) = @_;
my @list = split /\s+/, $line;		      # generate a list of callsigns

my $l;
my @out;

print "line: $line\n";
foreach $l (@list) {
  my @ans = Prefix::extract($l);
  print "ans:", @ans, "\n";
  next if !@ans;
  my $pre = shift @ans;
  my $a;
  foreach $a (@ans) {
    push @out, sprintf "%s   DXCC: %3d ITU: %3d CQ: %3d (%s, %s)", uc $l, $a->dxcc(), $a->itu(), $a->cq(), $pre, $a->name();
  }
}

return (1, @out);
