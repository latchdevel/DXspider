#
# show dx (normal)
#
# $Id$
#

my ($self, $line) = @_;
my @list = split /\s+/, $line;	# split the line up

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
my $qsl;

while ($f = shift @list) {		# next field
	#  print "f: $f list: ", join(',', @list), "\n";
	if (!$from && !$to) {
		($from, $to) = $f =~ /^(\d+)-(\d+)$/o; # is it a from -> to count?
		next if $from && $to > $from;
	}
	if (!$to) {
		($to) = $f =~ /^(\d+)$/o if !$to; # is it a to count?
		next if $to;
	}
	if (lc $f eq 'on' && $list[0]) { # is it freq range?
		#    print "yup freq\n";
		my @r = split '/', $list[0];
			# print "r0: $r[0] r1: $r[1]\n";
		my @fr = Bands::get_freq($r[0], $r[1]);
		if (@fr) {			# yup, get rid of extranous param
			#	  print "freq: ", join(',', @fr), "\n";
			shift @list;
			push @freq, @fr;    # add these to the list
			next;
		}
	}
	if (lc $f eq 'day' && $list[0]) {
		#   print "got day\n";
		($fromday, $today) = split '-', shift(@list);
		next;
	}
	if (lc $f eq 'info' && $list[0]) {
		#   print "got info\n";
		$info = shift @list;
		next;
	}
	if ((lc $f eq 'spotter' || lc $f eq 'by') && $list[0]) {
		#    print "got spotter\n";
		$spotter = uc shift @list;
		next;
	}
	if (lc $f eq 'qsl') {
		$doqsl = 1;
		next;
	}
	if (!$pre) {
		$pre = uc $f;
	}
}

# first deal with the prefix
if ($pre) {
	$pre .= '*' unless $pre =~ /[\*\?\[]/o;
	$pre = shellregex($pre);
	$expr = "\$f1 =~ m{$pre}o";
} else {
	$expr = "1";				# match anything
}
  
# now deal with any frequencies specified
if (@freq) {
	$expr .= ($expr) ? " && (" : "(";
	my $i;
	for ($i = 0; $i < @freq; $i += 2) {
		$expr .= "(\$f0 >= $freq[$i] && \$f0 <= $freq[$i+1]) ||";
	}
	chop $expr;
	chop $expr;
	$expr .= ")";
}

# any info
if ($info) {
	$expr .= " && " if $expr;
	$info =~ s{(.)}{"\Q$1"}ge;
	$expr .= "\$f3 =~ m{$info}io";
}

# any spotter
if ($spotter) {
	$expr .= " && " if $expr;
	$spotter = shellregex($spotter);
	$expr .= "\$f4 =~ m{$spotter}o";
}

# qsl requests
if ($doqsl) {
	$expr .= " && " if $expr;
	$expr .= "\$f3 =~ m{(QSL|VIA)}io";
}

#print "expr: $expr from: $from to: $to fromday: $fromday today: $today\n";
  
# now do the search
my @res = Spot::search($expr, $fromday, $today, $from, $to);
my $ref;
my @dx;
foreach $ref (@res) {
	@dx = @$ref;
	push @out, Spot::formatl(@dx);
}

return (1, @out);
