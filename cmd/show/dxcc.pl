#
# show dx using the dxcc number as the basis for searchs for each callsign or prefix entered
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
  my $expr;
  my $str = "Prefix: $pre";
  my $l = length $str;
  foreach $a (@ans) {
    $expr .= " || " if $expr;
	my $n = $a->dxcc();
    $expr .= "\$f5 == $n";
	my $name = $a->name();
	$str .= " Dxcc: $n ($name)";
	push @out, $str;
	$str = pack "A$l", " ";
  }
  push @out, $str;
  print "expr: $expr\n";
  my @res = Spot::search($expr);
  my $ref;
  my @dx;
  foreach $ref (@res) {
    @dx = @$ref;
	my $t = ztime($dx[2]);
	my $d = cldate($dx[2]);
	push @out, sprintf "%9s %-12s %s %s %-28s <%s>", $dx[0], $dx[1], $d, $t, $dx[3], $dx[4];
  }
}

return (1, @out);
