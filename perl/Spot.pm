#
# the dx spot handler
#
# Copyright (c) - 1998 Dirk Koopman G1TLH
#
# $Id$
#

package Spot;

use IO::File;
use DXVars;
use DXDebug;
use DXUtil;
use DXLog;
use Julian;
use Prefix;
use DXDupe;

use strict;
use vars qw($fp $maxspots $defaultspots $maxdays $dirprefix $duplth $dupage $filterdef);

$fp = undef;
$maxspots = 50;					# maximum spots to return
$defaultspots = 10;				# normal number of spots to return
$maxdays = 35;					# normal maximum no of days to go back
$dirprefix = "spots";
$duplth = 20;					# the length of text to use in the deduping
$dupage = 3*3600;               # the length of time to hold spot dups
$filterdef = bless ([
			  # tag, sort, field, priv, special parser 
			  ['freq', 'r', 0, 0, \&decodefreq],
			  ['call', 'c', 1],
			  ['info', 't', 3],
			  ['by', 'c', 4],
			  ['call_dxcc', 'n', 5],
			  ['by_dxcc', 'n', 6],
			  ['origin', 'c', 7, 9],
			  ['call_itu', 'n', 8],
			  ['call_zone', 'n', 9],
			  ['by_itu', 'n', 10],
			  ['by_zone', 'n', 11],
			  ['channel', 'n', 12, 9],
			 ], 'Filter::Cmd');


# create a Spot Object
sub new
{
	my $class = shift;
	my $self = [ @_ ];
	return bless $self, $class;
}

sub decodefreq
{
	my $dxchan = shift;
	my $l = shift;
	my @f = split /,/, $l;
	my @out;
	my $f;
	
	foreach $f (@f) {
		my ($a, $b); 
		if (m{^\d+/\d+$}) {
			push @out, $f;
		} elsif (($a, $b) = $f =~ m{^(\w+)(?:/(\w+))?$}) {
			$b = lc $b if $b;
			my @fr = Bands::get_freq(lc $a, $b);
			if (@fr) {
				while (@fr) {
					$a = shift @fr;
					$b = shift @fr;
					push @out, "$a/$b";  # add them as ranges
				}
			} else {
				return ('dfreq', $dxchan->msg('dfreq1', $f));
			}
		} else {
			return ('dfreq', $dxchan->msg('e20', $f));
		}
	}
	return (0, join(',', @out));			 
}

sub init
{
	mkdir "$dirprefix", 0777 if !-e "$dirprefix";
	$fp = DXLog::new($dirprefix, "dat", 'd');
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

	# normalise frequency
	$spot[0] = sprintf "%.f", $spot[0];
  
	# remove ssids if present on spotter
	$out[4] =~ s/-\d+$//o;

	# remove leading and trailing spaces
	$spot[3] = unpad($spot[3]);
	
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
  
	return (@out, $spotted_itu, $spotted_cq, $spotter_itu, $spotter_cq);
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
	my @today = Julian::unixtoj(time());
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

	for ($i = $count = 0; $i < $maxdays; ++$i) {	# look thru $maxdays worth of files only
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
	my $wantgrid = shift;
	my $t = ztime($_[2]);
	my $ref = DXUser->get_current($_[4]);
	my $loc = $ref->qra if $ref && $ref->qra && $wantgrid;
	$loc = ' ' . substr($ref->qra, 0, 4) if $loc;
	$loc = "" unless $loc;
	return sprintf "DX de %-7.7s%11.1f  %-12.12s %-30s %s$loc", "$_[4]:", $_[0], $_[1], $_[3], $t ;
}

# format a spot for user output in list mode
sub formatl
{
	my $t = ztime($_[2]);
	my $d = cldate($_[2]);
	return sprintf "%8.1f  %-11s %s %s  %-28.28s%7s>", $_[0], $_[1], $d, $t, $_[3], "<$_[4]" ;
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

# enter the spot for dup checking and return true if it is already a dup
sub dup
{
	my ($freq, $call, $d, $text) = @_; 

	# dump if too old
	return 2 if $d < $main::systime - $dupage;
 
	$freq = sprintf "%.1f", $freq;       # normalise frequency
	chomp $text;
	$text = substr($text, 0, $duplth) if length $text > $duplth; 
	unpad($text);
	$text =~ s/[^a-zA-Z0-9]//g;
	my $dupkey = "X$freq|$call|$d|\L$text";
	return DXDupe::check($dupkey, $main::systime+$dupage);
}

sub listdups
{
	return DXDupe::listdups('X', $dupage, @_);
}
1;




