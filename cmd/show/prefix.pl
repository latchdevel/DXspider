#
# show the prefix info for each callsign or prefix entered
#
# $Id$
#

my ($self, $line) = @_;
my @list = split /\s+/, $line;		      # generate a list of callsigns

my $l;
my @out;

#print "line: $line\n";
foreach $l (@list) {
  my @ans = Prefix::extract($l);
  #print "ans:", @ans, "\n";
  next if !@ans;
  my $pre = shift @ans;
  my $a;
  foreach $a (@ans) {
    push @out, sprintf "%s DXCC: %d ITU: %d CQ: %d LL: %s %s (%s, %s)", uc $l, $a->dxcc(), $a->itu(), $a->cq(), slat($a->lat), slong($a->long), $pre, $a->name();
	$l = " " x length $l;
  }
}

return (1, @out);
