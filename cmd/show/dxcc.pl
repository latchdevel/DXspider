#
# show dx using the dxcc number as the basis for searchs for each callsign or prefix entered
#
# $Id$
#

my ($self, $line) = @_;
my @list = split /\s+/, $line;		      # split the line up

my @out;
my $f;
my $call;
my ($from, $to);
my ($fromday, $today);
my @freq;
my @ans;

while ($f = shift @list) {                 # next field
  print "f: $f list: ", join(',', @list), "\n";
  if (!$from && !$to) {
    ($from, $to) = $f =~ /^(\d+)-(\d+)$/o;         # is it a from -> to count?
    next if $from && $to > $from;
  }
  if (!$to) {
    ($to) = $f =~ /^(\d+)$/o if !$to;              # is it a to count?
    next if $to;
  }
  if (lc $f eq 'on' && $list[0]) {                  # is it freq range?
    print "yup freq\n";
    my @r = split '/', $list[0];
	print "r0: $r[0] r1: $r[1]\n";
	@freq = Bands::get_freq($r[0], $r[1]);
	if (@freq) {                 # yup, get rid of extranous param
	  print "freq: ", join(',', @freq), "\n";
	  shift @list;
	  next;
	}
  }
  if (lc $f eq 'day' && $list[0]) {
    print "got day\n";
    ($fromday, $today) = split '-', $list[0];
	shift @list;
	next;
  }
  if (!@ans) {
    @ans = Prefix::extract($f);                       # is it a callsign/prefix?
  }
}

# no dxcc country, no answer!
if (@ans) {                               # we have a valid prefix!
  
  # first deal with the prefix
  my $pre = shift @ans;
  my $a;
  my $expr = "(";
  my $str = "Prefix: $pre";
  my $l = length $str;

  # build up a search string for this dxcc country/countries
  foreach $a (@ans) {
    $expr .= " || " if $expr ne "(";
	my $n = $a->dxcc();
    $expr .= "\$f5 == $n";
	my $name = $a->name();
	$str .= " Dxcc: $n ($name)";
	push @out, $str;
	$str = pack "A$l", " ";
  }
  $expr .= ")";
  push @out, $str;
  
  # now deal with any frequencies specified
  if (@freq) {
    $expr .= " && (";
	my $i;
	for ($i; $i < @freq; $i += 2) {
	  $expr .= "(\$f0 >= $freq[0] && \$f0 <= $freq[1]) ||";
	}
	chop $expr;
	chop $expr;
	$expr .= ")";
  }

  print "expr: $expr from: $from to: $to fromday: $fromday today: $today\n";
  
  # now do the search
  my @res = Spot::search($expr, $fromday, $today, $from, $to);
  my $ref;
  my @dx;
  foreach $ref (@res) {
    @dx = @$ref;
	my $t = ztime($dx[2]);
	my $d = cldate($dx[2]);
	push @out, sprintf "%9s %-12s %s %s %-28s <%s>", $dx[0], $dx[1], $d, $t, $dx[3], $dx[4];
  }
} else {
  @out = DXM::msg('e4');
}

return (1, @out);
