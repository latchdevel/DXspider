#!/usr/bin/perl
#
# show satellite az/el 
#
# copyright (c) 1999 Steve Franke K9AN
#
# $Id$
# 

my ($self, $line) = @_;
my @out;

my @f = split /\s+/, $line;
my $satname = uc shift @f;
my $numhours = shift @f;               # the number of hours ahead to print
my $step = shift @f;				# tracking table resolution in minutes

# default hours and step size
$numhours = 3 unless $numhours && $numhours =~ /^\d+$/;
$step = 5 unless $step && $step =~ /^\d+$/;

# get nearest lat and long (I can see we will need the altitude here soon as well :-)
my $lat = $self->user->lat;
my $lon = $self->user->long;
my $alt = 0;
my $call = $self->call;
unless ($lon || $lat) {
	$lat = $main::mylatitude;
	$lon = $main::mylongitude;
	$call = $main::mycall;
}

if ($satname && $Sun::keps{$satname}) {
	my $jtime; # lats and longs in radians
	my ($sec, $min, $hr, $day, $mon, $yr) = (gmtime($main::systime))[0,1,2,3,4,5];
	#printf("%2.2d %2.2d %2.2d %2.2d %2.2d\n",$min,$hr,$day,$mon,$yr);

	$mon++;
	$yr += 1900;
	$alt=0.0;

	$jtime=Sun::Julian_Day($yr,$mon,$day)+$hr/24+$min/60/24;
	($yr,$mon,$day,$hr,$min)=Sun::Calendar_date_and_time_from_JD($jtime);
	#printf("%2.2d %2.2d %2.2d %2.2d %2.2d\n",$min,$hr,$day,$mon,$yr);
	push @out, $self->msg("pos", $call, slat($lat), slong($lon));
	push @out, $self->msg("sat1", $satname, $numhours, $step);
	push @out, $self->msg("sat2");
	
	my ($slat,$slon,$salt,$az,$el,$distance)=Sun::get_satellite_pos($jtime,$lat*$d2r,$lon*$d2r,$alt,$satname);
	# print the current satellite position
	push @out,sprintf("Now   %2.2d:%2.2d %7.1f %7.1f %7.1f %7.1f %7.1f %7.1f", 
					  $hr,$min,$slat*$r2d,$slon*$r2d,$salt,
					  $az*$r2d,$el*$r2d,$distance);

	my $numsteps=0;
	$jtime=$jtime+$step/24/60;
	my $disc = 0;             # discontinuity flag
	while ( $numsteps < $numhours*60/$step ) # look $numhours  ahead for tracking table
	{
		my ($yr,$mon,$day,$hr,$min)=Sun::Calendar_date_and_time_from_JD($jtime);
		my ($slat,$slon,$salt,$az,$el,$distance)=Sun::get_satellite_pos($jtime,$lat*$d2r,$lon*$d2r,$alt,$satname);
		if ( $el*$r2d > -5 ) {
			if ($disc) {
				$disc = 0;
				push @out, $self->msg("satdisc");
			}
			push @out,sprintf("%2.2d/%2.2d %2.2d:%2.2d %7.1f %7.1f %7.1f %7.1f %7.1f %7.1f", 
							  $day,$mon,$hr,$min,$slat*$r2d,$slon*$r2d,$salt,
							  $az*$r2d,$el*$r2d,$distance);
		} else {
			$disc++;
		}
		$numsteps++;
		$jtime=$jtime+$step/60/24;
	}
} else {
	push @out, $self->msg("satnf", $satname) if $satname;
	push @out, $self->msg("sat3");
	push @out, $self->msg("sat4");
	my @l;
	my $i = 0;
	my $sat;
	foreach $sat (sort keys %Sun::keps) {
		if ($i >= 6) {
			push @out, join ' + ', @l;
			@l = ();
			$i = 0;
		}
		push @l, $sat;
		$i++;
	}
	push @out, join ' + ', @l;
}

return (1,@out);











