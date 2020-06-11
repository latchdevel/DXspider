#
# show the prefix info for each callsign or prefix entered
#
#
#

my ($self, $line) = @_;
my @list = split /\s+/, $line;	# generate a list of callsigns

my $l;
my @out;

#$DB::single = 1;

#print "line: $line\n";
foreach $l (@list) {
	my @ans = Prefix::extract($l);
	next if !@ans;
#	dbg(join(', ', @ans));
	my $pre = shift @ans;
	my $a;
	foreach $a (@ans) {
		push @out, substr(sprintf("%s CC: %d IZ: %d CZ: %d LL: %s %s %4.4s (%s, %s", uc $l, $a->dxcc, $a->itu, $a->cq, slat($a->lat), slong($a->long), $a->qra, $pre, $a->name), 0, 78) . ')';
		$l = " " x length $l;
	}
	if ($USDB::present && $ans[0]->state) {
		push @out, sprintf "%s City: %s State: %s", $l, join (' ', map {ucfirst} split(/\s+/, lc $ans[0]->city)), $ans[0]->state;
	}
	
}

return (1, @out);
