#
# show the distance and bearing to a  QRA locator
#
# you can enter two qra locators and it will calc the distance between them
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
	$lat = $main::mylatitude;
	$long = $main::mylongitude;
}

return (1, $self->msg('qrashe1')) unless @list > 0;
return (1, $self->msg('qrae2')) unless (DXBearing::is_qra($list[0]) || $list[0] =~ /^[A-Za-z][A-Za-z]\d\d$/);

#print "$lat $long\n";

my $l = uc $list[0];
my $f;

if (@list > 1) {
	$f = $l;
	$f .= 'MM' if $f =~ /^[A-Z][A-Z]\d\d$/;
	($lat, $long) = DXBearing::qratoll($f);
    #print "$lat $long\n";
	
	return (1, $self->msg('qrae2')) unless (DXBearing::is_qra($list[1]) || $list[1] =~ /^[A-Za-z][A-Za-z]\d\d$/);
	$l = uc $list[1];
}

$l .= 'MM' if $l =~ /^[A-Z][A-Z]\d\d$/;
		
my ($qlat, $qlong) = DXBearing::qratoll($l);
#print "$qlat $qlong\n";
my ($b, $dx) = DXBearing::bdist($lat, $long, $qlat, $qlong);
my ($r, $rdx) = DXBearing::bdist($qlat, $qlong, $lat, $long);
my $to = " -> $list[1]" if $f;
my $from = $list[0];

push @out, sprintf "$list[0]$to Bearing: %.0f Deg. Recip: %.0f Deg. %.0fMi. %.0fKm.", $b, $r, $dx * 0.62133785, $dx;

return (1, @out);
