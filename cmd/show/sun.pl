#!/usr/bin/perl
#
# show sunrise and sunset times for each callsign or prefix entered
#
# 1999/11/9 Steve Franke K9AN
#

my ($self, $line) = @_;
my @list = split /\s+/, $line;

my $l;
my @out;
my ($lat, $lon);              # lats and longs in radians
my ($sec, $min, $hr, $day, $month, $yr) = (gmtime($main::systime))[0,1,2,3,4,5];
$month++;
$yr += 1900;

foreach $l (@list) {
	# prefixes --->
	my @ans = Prefix::extract($l);
	next if !@ans;
	my $pre = shift @ans;
	my $a;
	foreach $a (@ans) {
		$lat = $a->{lat};
		$lon = $a->{long};
		$lat *= $d2r;
		$lon *= -$d2r;
		my $string=Sun::riseset($yr,$month,$day,$lat,$lon);
		push @out,sprintf("%-2s   %s   %s",$pre,$a->name(),$string);
		$l="";
	}
}

return (1, @out);
