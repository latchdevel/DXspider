#
# show the heading and distance for each callsign or prefix entered
#
# $Id$
#

my ($self, $line) = @_;
my @list = split /\s+/, $line;		      # generate a list of callsigns

my $l;
my @out;
my $lat = $self->user->lat;
my $long = $self->user->long;
if (!$long && !$lat) {
	push @out, $self->msg('heade1');
	$lat = $main::mylat;
	$long = $main::mylong;
}

foreach $l (@list) {
	# prefixes --->
	my @ans = Prefix::extract($l);
	next if !@ans;
	my $pre = shift @ans;
	my $a;
	foreach $a (@ans) {
		my ($b, $dx) = DXBearing::bdist($lat, $long, $a->{lat}, $a->{long});
		my ($r, $rdx) = DXBearing::bdist($a->{lat}, $a->{long}, $lat, $long);
		push @out, sprintf "%-9s (%s, %s) Bearing: %.0f Recip: %.0f %.0fKm %.0fMi", uc $l, $pre, $a->name(), $b, $r, $dx, $dx * 0.62133785;
		$l = "";
	}
}

return (1, @out);
