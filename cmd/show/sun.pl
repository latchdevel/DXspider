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

my @in;

if (@list) {
	foreach $l (@list) {
		my $user = DXUser->get_current(uc $l);
		if ($user && $user->lat && $user->long) {
			push @in, [$user->qth, $user->lat * $d2r, $user->long * -$d2r, uc $l ];
		} else {
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
				push @in, [ $a->name, $lat, $lon, $pre ];
			}
		}
	}
} else {
	if ($self->user->lat && $self->user->long) {
		push @in, [$self->user->qth, $self->user->lat * $d2r, $self->user->long * -$d2r, $self->call ];
	} else {
		push @in, [$main::myqth, $main::mylatitude * $d2r, $main::mylogitude * -$d2r, $main::mycall ];
	}
}

foreach $l (@in) {
	my $string=Sun::riseset($yr,$month,$day,$l->[1],$l->[2]);
	push @out,sprintf("%-2s   %s   %s",$l->[3],$l->[0],$string);
}

			

return (1, @out);
