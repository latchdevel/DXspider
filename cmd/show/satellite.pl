#!/usr/bin/perl
#
# show satellite az/el 
#
# 1999/12/9 Steve Franke K9AN
#
# 

my ($self, $satname) = @_;
my @out;

my ($lat, $lon, $alt, $jtime); # lats and longs in radians
my ($sec, $min, $hr, $day, $mon, $yr) = (gmtime($main::systime))[0,1,2,3,4,5];
#printf("%2.2d %2.2d %2.2d %2.2d %2.2d\n",$min,$hr,$day,$mon,$yr);

$mon++;
$yr += 1900;
$lat=$main::mylatitude;
$lon=$main::mylongitude;
$alt=0.0;

$jtime=Sun::Julian_Day($yr,$mon,$day)+$hr/24+$min/60/24;
($yr,$mon,$day,$hr,$min)=Sun::Calendar_date_and_time_from_JD($jtime);
#printf("%2.2d %2.2d %2.2d %2.2d %2.2d\n",$min,$hr,$day,$mon,$yr);
push @out,sprintf("Tracking table for $satname");
push @out,sprintf("dd/mm  UTC   Lat    Lon    Alt(km)  Az     El   Dist(km)");
my ($slat,$slon,$salt,$az,$el,$distance)=
	Sun::get_satellite_pos(
  	  $jtime,$lat*$d2r,$lon*$d2r,$alt,$satname);
push @out,sprintf(   # print the current satellite position
	"Now   %2.2d:%2.2d %6.1f %6.1f %6.1f  %6.1f %6.1f %6.1f", 
	$hr,$min,$slat*$r2d,$slon*$r2d,$salt,
	$az*$r2d,$el*$r2d,$distance);

my $numsteps=0;
my $step = 2; # tracking table resolution in minutes
$jtime=$jtime+$step/24/60;
while ( $numsteps < 6*60/$step ) # for now, look 6 hours ahead for tracking table
	{
	my ($yr,$mon,$day,$hr,$min)=Sun::Calendar_date_and_time_from_JD($jtime);
	my ($slat,$slon,$salt,$az,$el,$distance)=
		Sun::get_satellite_pos(
		$jtime,$lat*$d2r,$lon*$d2r,$alt,$satname);
	if( $el*$r2d > -5 ) {
		push @out,sprintf(
			"%2.2d/%2.2d %2.2d:%2.2d %6.1f %6.1f %6.1f  %6.1f %6.1f %6.1f", 
			$day,$mon,$hr,$min,$slat*$r2d,$slon*$r2d,$salt,
			$az*$r2d,$el*$r2d,$distance);
		}
	$numsteps++;
	$jtime=$jtime+$step/60/24;
	}

return (1,@out);


