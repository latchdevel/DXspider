#
# the dx spot handler
#
# Copyright (c) - 1998 Dirk Koopman G1TLH
#
# $Id$
#

package Spot;

use FileHandle;
use DXVars;
use DXDebug;
use DXUtil;
use DXLog;
use Julian;
use Prefix;
use Carp;

use strict;
use vars qw($fp $maxspots $defaultspots $maxdays $dirprefix);

$fp = undef;
$maxspots = 50;					# maximum spots to return
$defaultspots = 10;				# normal number of spots to return
$maxdays = 35;					# normal maximum no of days to go back
$dirprefix = "spots";

sub init
{
	mkdir "$dirprefix", 0777 if !-e "$dirprefix";
	$fp = DXLog::new($dirprefix, "dat", 'd')
}

sub prefix
{
	return $fp->{prefix};
}

# add a spot to the data file (call as Spot::add)
sub add
{
	my @spot = @_;				# $freq, $call, $t, $comment, $spotter = @_
	my @out = @spot[0..4];      # just up to the spotter
	
	# sure that the numeric things are numeric now (saves time later)
	$spot[0] = 0 + $spot[0];
	$spot[2] = 0 + $spot[2];
  
	# remove ssids if present on spotter
	$out[4] =~ s/-\d+$//o;

	# add the 'dxcc' country on the end for both spotted and spotter, then the cluster call
	my @dxcc = Prefix::extract($out[1]);
	my $spotted_dxcc = (@dxcc > 0 ) ? $dxcc[1]->dxcc() : 0;
	my $spotted_itu = (@dxcc > 0 ) ? $dxcc[1]->itu() : 0;
	my $spotted_cq = (@dxcc > 0 ) ? $dxcc[1]->cq() : 0;
	push @out, $spotted_dxcc;
	@dxcc = Prefix::extract($out[4]);
	my $spotter_dxcc = (@dxcc > 0 ) ? $dxcc[1]->dxcc() : 0;
	my $spotter_itu = (@dxcc > 0 ) ? $dxcc[1]->itu() : 0;
	my $spotter_cq = (@dxcc > 0 ) ? $dxcc[1]->cq() : 0;
	push @out, $spotter_dxcc;
	push @out, $spot[5];
	
	my $buf = join("\^", @out);

	# compare dates to see whether need to open another save file (remember, redefining $fp 
	# automagically closes the output file (if any)). 
	$fp->writeunix($out[2], $buf);
  
	return (@spot, $spotted_itu, $spotted_cq, $spotter_itu, $spotter_cq);
}

# search the spot database for records based on the field no and an expression
# this returns a set of references to the spots
#
# the expression is a legal perl 'if' statement with the possible fields indicated
# by $f<n> where :-
#
#   $f0 = frequency
#   $f1 = call
#   $f2 = date in unix format
#   $f3 = comment
#   $f4 = spotter
#   $f5 = spotted dxcc country
#   $f6 = spotter dxcc country
#   $f7 = origin
#
#
# In addition you can specify a range of days, this means that it will start searching
# from <n> days less than today to <m> days less than today
#
# Also you can select a range of entries so normally you would get the 0th (latest) entry
# back to the 5th latest, you can specify a range from the <x>th to the <y>the oldest.
#
# This routine is designed to be called as Spot::search(..)
#

sub search
{
	my ($expr, $dayfrom, $dayto, $from, $to) = @_;
	my $eval;
	my @out;
	my $ref;
	my $i;
	my $count;
	my @today = Julian::unixtoj(time);
	my @fromdate;
	my @todate;

	$dayfrom = 0 if !$dayfrom;
	$dayto = $maxdays if !$dayto;
	@fromdate = Julian::sub(@today, $dayfrom);
	@todate = Julian::sub(@fromdate, $dayto);
	$from = 0 unless $from;
	$to = $defaultspots unless $to;
	
	$to = $from + $maxspots if $to - $from > $maxspots || $to - $from <= 0;

	$expr =~ s/\$f(\d)/\$ref->[$1]/g; # swap the letter n for the correct field name
	#  $expr =~ s/\$f(\d)/\$spots[$1]/g;               # swap the letter n for the correct field name
  
	dbg("search", "expr='$expr', spotno=$from-$to, day=$dayfrom-$dayto\n");
  
	# build up eval to execute
	$eval = qq(
			   my \$c;
			   my \$ref;
			   for (\$c = \$#spots; \$c >= 0; \$c--) {
					\$ref = \$spots[\$c];
					if ($expr) {
						\$count++;
						next if \$count < \$from; # wait until from 
						push(\@out, \$ref);
						last if \$count >= \$to; # stop after to
					}
				}
			  );

	$fp->close;					# close any open files

	for ($i = 0; $i < $maxdays; ++$i) {	# look thru $maxdays worth of files only
		my @now = Julian::sub(@fromdate, $i); # but you can pick which $maxdays worth
		last if Julian::cmp(@now, @todate) <= 0;         
	
		my @spots = ();
		my $fh = $fp->open(@now); # get the next file
		if ($fh) {
			my $in;
			while (<$fh>) {
				chomp;
				push @spots, [ split '\^' ];
			}
			eval $eval;			# do the search on this file
			last if $count >= $to; # stop after to
			return ("Spot search error", $@) if $@;
		}
	}

	return @out;
}

# format a spot for user output in 'broadcast' mode
sub formatb
{
	my @dx = @_;
	my $t = ztime($dx[2]);
	return sprintf "DX de %-7.7s%11.1f  %-12.12s %-30s %s", "$dx[4]:", $dx[0], $dx[1], $dx[3], $t ;
}

# format a spot for user output in list mode
sub formatl
{
	my @dx = @_;
	my $t = ztime($dx[2]);
	my $d = cldate($dx[2]);
	return sprintf "%8.1f  %-11s %s %s  %-28.28s%7s>", $dx[0], $dx[1], $d, $t, $dx[3], "<$dx[4]" ;
}

#
# return all the spots from a day's file as an array of references
# the parameter passed is a julian day
sub readfile
{
	my @spots;
	
	my $fh = $fp->open(@_); 
	if ($fh) {
		my $in;
		while (<$fh>) {
			chomp;
			push @spots, [ split '\^' ];
		}
	}
	return @spots;
}
1;
