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
my $hint;
my $dxcc;
my $real;
my $fromdxcc;
my ($doqsl, $doiota, $doqra);

while ($f = shift @list) {		# next field
	#  print "f: $f list: ", join(',', @list), "\n";
	if (!$from && !$to) {
		($from, $to) = $f =~ m|^(\d+)[-/](\d+)$|; # is it a from -> to count?
		next if $from && $to > $from;
	}
	if (!$to) {
		($to) = $f =~ /^(\d+)$/o if !$to; # is it a to count?
		next if $to;
	}
	if (lc $f eq 'dxcc') {
		$dxcc = 1;
		next;
	}
	if (lc $f eq 'rt' || $f =~ /^real/i) {
		$real = 1;
		next;
	}
	if (lc $f eq 'on' && $list[0]) { # is it freq range?
		#    print "yup freq\n";
		if ($list[0] =~ m|^(\d+)(?:\.\d+)?[-/](\d+)(?:\.\d+)?$|) {
			push @freq, $1, $2;
			shift @list;
			next;
		} else {
			my @r = split '/', lc $list[0];
			# print "r0: $r[0] r1: $r[1]\n";
			my @fr = Bands::get_freq($r[0], $r[1]);
			if (@fr) {			# yup, get rid of extranous param
				#	  print "freq: ", join(',', @fr), "\n";
				push @freq, @fr;    # add these to the list
				shift @list;
				next;
			}
		}
	}
	if (lc $f eq 'day' && $list[0]) {
		#   print "got day\n";
		($fromday, $today) = split m|[-/]|, shift(@list);
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
		if ($list[0] && lc $list[0] eq 'dxcc') {
			$fromdxcc = 1;
			shift @list;
		}
		next;
	}
	if (lc $f eq 'qsl') {
		$doqsl = 1;
		next;
	}
	if (lc $f eq 'iota') {
		my ($a, $b);
#		$DB::single =1;
		
		if (@list && $list[0] && (($a, $b) = $list[0] =~ /(AF|AN|NA|SA|EU|AS|OC)-?(\d?\d\d)/oi)) {
			$a = uc $a;
			$doiota = "\\b$a\[\-\ \]\?$b\\b";
			shift @list;
		}
		$doiota = '\b(IOTA|(AF|AN|NA|SA|EU|AS|OC)[- ]?\d?\d\d)\b' unless $doiota;
		next;
	}
	if (lc $f eq 'qra') {
		$doqra = uc shift @list if @list && $list[0] =~ /[A-Z][A-Z]\d\d/oi;
		$doqra = '\b([A-Z][A-Z]\d\d|[A-Z][A-Z]\d\d[A-Z][A-Z])\b' unless $doqra;
		next;
	}
	if (!$pre) {
		$pre = uc $f;
	}
}

# first deal with the prefix
if ($pre) {
	my @ans;
	
	if ($dxcc) {
		@ans = Prefix::extract($pre);	# is it a callsign/prefix?
		
		if (@ans) {

			# first deal with the prefix
			my $pre = shift @ans;
			my $a;
			my $str = "Prefix: $pre";
			my $l = length $str;
			my @expr;
			my @hint;
			
			# build up a search string for this dxcc country/countries
			foreach $a (@ans) {
				my $n = $a->dxcc();
			    push @expr, "\$f5 == $n";
				push @hint, "m{$n}";
				my $name = $a->name();
				$str .= " Dxcc: $n ($name)";
				push @out, $str;
				$str = ' ' x $l;
			}
			$expr = @expr > 1 ? '(' . join(' || ', @expr) . ')' : $expr[0];
			$hint = @hint > 1 ? '(' . join(' || ', @hint) . ')' : $hint[0];
		}
	} 
	unless (@ans) {
		$pre .= '*' unless $pre =~ /[\*\?\[]/o;
		$pre = shellregex($pre);
		$expr = "\$f1 =~ m{$pre}";
		$pre =~ s/[\^\$]//g;
		$hint = "m{\U$pre}";
	}
}
  
# now deal with any frequencies specified
if (@freq) {
	$expr .= ($expr) ? " && (" : "(";
	$hint .= ($hint) ? " && (" : "(";
	my $i;
	for ($i = 0; $i < @freq; $i += 2) {
		$expr .= "(\$f0 >= $freq[$i] && \$f0 <= $freq[$i+1]) ||";
		my $r = Spot::ftor($freq[$i], $freq[$i+1]);
#		$hint .= "m{$r\\.} ||" if $r;
#		$hint .= "m{\d+\.} ||";
		$hint .= "1 ||";
	}
	chop $expr;	chop $expr;
	chop $hint;	chop $hint;
	$expr .= ")";
	$hint .= ")";
}

# any info
if ($info) {
	$expr .= " && " if $expr;
	$info =~ s{(.)}{"\Q$1"}ge;
	$expr .= "\$f3 =~ m{$info}i";
	$hint .= " && " if $hint;
	$hint .= "m{$info}i";
}

# any spotter
if ($spotter) {
	
	if ($fromdxcc) {
		@ans = Prefix::extract($spotter);	# is it a callsign/prefix?
		
		if (@ans) {

			# first deal with the prefix
			my $pre = shift @ans;
			my $a;
			$expr .= ' && ' if $expr;
			$hint .= ' && ' if $hint;
			my $str = "Spotter: $pre";
			my $l = length $str;
			my @expr;
			my @hint;
			
			# build up a search string for this dxcc country/countries
			foreach $a (@ans) {
				my $n = $a->dxcc();
			    push @expr, "\$f6 == $n";
				push @hint, "m{$n}";
				my $name = $a->name();
				$str .= " Dxcc: $n ($name)";
				push @out, $str;
				$str = ' ' x $l;
			}
			$expr .= @expr > 1 ? '(' . join(' || ', @expr) . ')' : $expr[0];
			$hint .= @hint > 1 ? '(' . join(' || ', @hint) . ')' : $hint[0];
		}
	} 
	unless (@ans) {
		$expr .= " && " if $expr;
		$spotter .= '*' unless $spotter =~ /[\*\?\[]/o;
		$spotter = shellregex($spotter);
		$expr .= "\$f4 =~ m{\U$spotter}";
		$hint .= " && " if $hint;
		$spotter =~ s/[\^\$]//g;
		$hint .= "m{\U$spotter}";
	}
}

# qsl requests
if ($doqsl) {
	$expr .= " && " if $expr;
	$expr .= "\$f3 =~ m{QSL|VIA}i";
	$hint .= " && " if $hint;
	$hint .= "m{QSL|VIA}i";
}

# iota requests
if ($doiota) {
	$expr .= " && " if $expr;
	$expr .= "\$f3 =~ m{$doiota}i";
	$hint .= " && " if $hint;
	$hint .= "m{$doiota}i";
}

# iota requests
if ($doqra) {
	$expr .= " && " if $expr;
	$expr .= "\$f3 =~ m{$doqra}i";
	$hint .= " && " if $hint;
	$hint .= "m{$doqra}io";
}

#print "expr: $expr from: $from to: $to fromday: $fromday today: $today\n";
  
# now do the search
my @res = Spot::search($expr, $fromday, $today, $from, $to, $hint);
my $ref;
my @dx;
foreach $ref (@res) {
	if ($real) {
		push @out, $self->format_dx_spot(@$ref);
	} else {
		push @out, Spot::formatl(@$ref);
	}
}

return (1, @out);
