#
# show the distance and bearing each QRA locator
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
	# locators --->
	if (DXBearing::is_qra($l) || $l =~ /^[A-Za-z][A-Za-z]\d\d$/) {
		my $qra = uc $l;
		$qra .= 'MM' if $l =~ /^[A-Za-z][A-Za-z]\d\d$/;
		
		my ($qlat, $qlong) = DXBearing::qratoll($qra);
		my ($b, $dx) = DXBearing::bdist($lat, $long, $qlat, $qlong);
		my ($r, $rdx) = DXBearing::bdist($qlat, $qlong, $lat, $long);
		push @out, sprintf "%-9s Bearing: %.0f Recip: %.0f %.0fKm %.0fMi", $qra, $b, $r, $dx, $dx * 0.62133785;
	}
}

return (1, @out);
