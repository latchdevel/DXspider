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
				$lon = -$a->{long};
				push @in, [ $a->name, $lat, $lon, $pre ];
			}
		}
	}
} else {
	if ($self->user->lat && $self->user->long) {
		push @in, [$self->user->qth, $self->user->lat, -$self->user->long, $self->call ];
	} else {
		push @in, [$main::myqth, $main::mylatitude, -$main::mylongitude, $main::mycall ];
	}
}

push @out, "                                      Rise   Set      Azim   Elev";
foreach $l (@in) {
	my ($rise, $set, $az, $dec )=Sun::rise_set($yr,$month,$day,$hr,$min,$l->[1],$l->[2],0);
	$l->[3] =~ s{(-\d+|/\w+)$}{};
	push @out,sprintf("%-6.6s %-30.30s %s %s %6.1f %6.1f ", $l->[3], $l->[0], $rise, $set, $az, $dec);
}

			

return (1, @out);
