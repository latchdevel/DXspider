#!/usr/bin/perl -w

# $Id$

# this has been taken from Geo::METAR
#
# Brief Description
# =================
#
# fetch_temp.pl is a program that demonstrates how to get the current
# temperature from a nearby (or not) airport using Geo::METAR and the
# LWP modules.
#
# Given an airport site code on the command line, fetch_temp.pl
# fetches the current temperature and displays it on the
# command-line. For fun, here are some example airports:
#
# LA     : KLAX
# Dallas : KDFW
# Detroit: KDTW
# Chicago: KMDW
#
# and of course: EGSH (Norwich)
#
#
# Get the site code.

my $site_code = uc shift @ARGV;

die "Usage: $0 <site_code>\n" unless $site_code;

# Get the modules we need.

use Geo::TAF;
use LWP::UserAgent;
use strict;

my $ua = new LWP::UserAgent;

my $req = new HTTP::Request GET =>
  "http://weather.noaa.gov/cgi-bin/mgetmetar.pl?cccc=$site_code";

my $response = $ua->request($req);

if (!$response->is_success) {

    print $response->error_as_HTML;
    my $err_msg = $response->error_as_HTML;
    warn "$err_msg\n\n";
    die "$!";

} else {

    # Yep, get the data and find the METAR.

    my $m = new Geo::TAF;
    my $data;
    $data = $response->as_string;               # grap response
    $data =~ s/\n//go;                          # remove newlines
    $data =~ m/($site_code\s\d+Z.*?)</go;       # find the METAR string
    my $metar = $1;                             # keep it

    # Sanity check

    if (length($metar)<10) {
        die "METAR is too short! Something went wrong.";
    }

    # pass the data to the METAR module.
    $m->metar($metar);

    print $m->as_string, "\n";

} # end else

exit;

__END__


