#
# show dx (normal)
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
my $pre;
my $spotter;
my $info;
my $expr;

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
    ($fromday, $today) = split '-', shift(@list);
	next;
  }
  if (lc $f eq 'info' && $list[0]) {
    print "got info\n";
	$info = shift @list;
	next;
  }
  if (lc $f eq 'spotter' && $list[0]) {
    print "got spotter\n";
	$spotter = uc shift @list;
	next;
  }
  if (!$pre) {
    $pre = uc $f;
  }
}

# first deal with the prefix
if ($pre) {
  $expr = "\$f1 =~ /";
  $pre =~ s|/|\\/|;          # change the slashes to \/ 
  if ($pre =~ /^\*/o) {
    $pre =~ s/^\*//;;
    $expr .= "$pre\$/o";
  } else {
	$expr .= "^$pre/o";
  }
} else {
  $expr = "1";             # match anything
}
  
# now deal with any frequencies specified
if (@freq) {
  $expr .= ($expr) ? " && (" : "(";
  my $i;
  for ($i; $i < @freq; $i += 2) {
    $expr .= "(\$f0 >= $freq[$i] && \$f0 <= $freq[$i+1]) ||";
  }
  chop $expr;
  chop $expr;
  $expr .= ")";
}

# any info
if ($info) {
  $expr .= " && " if $expr;
  $info =~ s|/|\\/|;
  $expr .= "\$f3 =~ /$info/io";
}

# any spotter
if ($spotter) {
  $expr .= " && " if $expr;
  $spotter =~ s|/|\\/|;
  $expr .= "\$f4 =~ /$spotter/o";
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

return (1, @out);
