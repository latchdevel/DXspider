#!/usr/bin/perl
# a program to create a prefix file from a wpxloc.raw file
#
# Copyright (c) - Dirk Koopman G1TLH
#
# $Id$
#

require 5.004;

# search local then perl directories
BEGIN {
	# root of directory tree for this system
	$root = "/spider"; 
	$root = $ENV{'DXSPIDER_ROOT'} if $ENV{'DXSPIDER_ROOT'};
	
	unshift @INC, "$root/perl";	# this IS the right way round!
	unshift @INC, "$root/local";
}

use DXVars;
use Data::Dumper;
use strict;

my %loc = ();						# the location unique hash
my $nextloc = 1;					# the next location number
my %locn = ();						# the inverse of the above
my %pre = ();						# the prefix hash
my %pren = ();						# the inverse

# open the input file
my $ifn = $ARGV[0] if $ARGV[0];
$ifn = "$main::data/wpxloc.raw" if !$ifn;
open (IN, $ifn) or die "can't open $ifn ($!)";

# first pass, find all the 'master' location records
while (<IN>) {
	next if /^\!/;				# ignore comment lines
	chomp;
	my @f  = split;				# get each 'word'
	next if @f == 0;			# ignore blank lines

	if (($f[14] && $f[14] eq '@') || ($f[15] && $f[15] eq '@')) {
		my $locstr = join ' ', @f[1..13];
		my $loc = $loc{$locstr};
		$loc = addloc($locstr) if !$loc;
	}
}

#foreach $loc (sort {$a <=> $b;} keys %locn) {
#  print "loc: $loc data: $locn{$loc}\n";
#}

# go back to the beginning and this time add prefixes (adding new location entries, if required)
seek(IN, 0, 0);

my $line;
while (<IN>) {
	$line++;
	chomp;
	next if /^\s*\!/;				# ignore comment lines
	next if /^\s*$/;
	
	my @f  = split;				# get each 'word'
	next if @f == 0;			# ignore blank lines
  
	# location record
	my $locstr = join ' ', @f[1..13];
	my $loc = $loc{$locstr};
	$loc = addloc($locstr) if !$loc;
  
	my @prefixes = split /,/, $f[0];
	foreach my $p (@prefixes) {
		my $ref;
	
		if ($p =~ /#/) {
			my $i;
			for ($i = 0; $i < 9; ++$i) {
				my $t = $p;
				$t =~ s/#/$i/;
				addpre($t, $loc);
			}
		} else {
			addpre($p, $loc);
		}	
	}
}

close(IN);

#print Data::Dumper->Dump([\%pre, \%locn], [qw(pre locn)]);

# now open the rsgb.cty file and process that again the prefix file we have
open(IN, "$main::data/rsgb.cty") or die "Can't open $main::data/rsgb.cty ($!)";
$line = 0;
while (<IN>) {
	$line++;
	next if /^\s*#/;
	next if /^\s*$/;
	my $l = $_;
	chomp;
	my @f = split /:\s+|;/;
	my $p = uc $f[4];
	my $ref = $pre{$p};
	if ($ref) {
		# split up the alias string
		my @alias = split /=/, $f[5];
		my $a;
		foreach $a (@alias) {
			next if $a eq $p;	# ignore if we have it already
			my $nref = $pre{$a};
			$pre{$a} = $ref if !$nref; # copy the original ref if new 
		}
	} else {
		print "line $line: unknown prefix '$p' on $l in rsgb.cty\n";
	}
}
close IN;

# now open the cty.dat file if it is there
my @f;
my @a;
$line = 0;
if (open(IN, "$main::data/cty.dat")) {
	my $state = 0;
	while (<IN>) {
		$line++;
		s/\r$//;
		next if /^\s*\#/;
		next if /^\s*$/;
		chomp;
		if ($state == 0) {
			s/:$//;
			@f = split /:\s+/;
			@a = ();
			$state = 1;
		} elsif ($state == 1) {
			s/^\s+//;
			if (/;$/) {
				$state = 0;
				s/[,;]$//;
				push @a, split /\s*,/;
				next if $f[7] =~ /^\*/;   # ignore callsigns starting '*'
				ct($_, uc $f[7], @a) if @a;
			} else {
				s/,$//;
				push @a, split /\s*,/;
			}
		}
	}
}
close IN;


open(OUT, ">$main::data/prefix_data.pl") or die "Can't open $main::data/prefix_data.pl ($!)";

print OUT "\%pre = (\n";
foreach my $k (sort keys %pre) {
	my $ans = printpre($k);
	print OUT "  '$k' => '$ans',\n";
}
print OUT ");\n\n";

print OUT "\n\%prefix_loc = (\n";
foreach my $l (sort {$a <=> $b} keys %locn) {
	print OUT "   $l => bless( {";
	my ($name, $dxcc, $itu, $cq, $utcoff, $latd, $latm, $lats, $latl, $longd, $longm, $longs, $longl) = split /\s+/, $locn{$l};
  
	$longd += ($longm/60);
	$longd = 0-$longd if (uc $longl) eq 'W'; 
	$latd += ($latm/60);
	$latd = 0-$latd if (uc $latl) eq 'S';
	print OUT " name => '$name',";
	print OUT " dxcc => $dxcc,";
	print OUT " itu => $itu,";
	print OUT " cq => $cq,";
	print OUT " utcoff => $utcoff,";
	print OUT " lat => $latd,";
	print OUT " long => $longd";
	print OUT " }, 'Prefix'),\n";
}
print OUT ");\n\n";

close(OUT);

sub addpre
{
	my ($p, $ent) = @_;
	my $ref = $pre{$p};
	$ref = $pre{$p} = [] if !$ref;
	push @{$ref}, $ent;;
}

sub printpre
{
	my $p = shift;
	my $ref = $pre{$p};
	my $out;
	my $r;
  
	foreach $r (@{$ref}) {
		$out .= "$r,";
	}
	chop $out;
	return $out;
}

sub ct
{
	my $l = shift;
	my $p = shift; 
	my @a = @_;
	my $ref = $pre{$p};
	if ($ref) {
		my $a;
		foreach $a (@a) {
			# for now remove (nn) [nn]
			$a =~ s/(?:\(\d+\)|\[\d+\])//g;
			unless ($a) {
				print "line $line: blank prefix on $l in cty.dat\n";
				next;
			}
			next if $a eq $p;	# ignore if we have it already
			my $nref = $pre{$a};
			$pre{$a} = $ref if !$nref; # copy the original ref if new 
		}
	} else {
		print "line $line: unknown prefix '$p' on $l in cty.dat\n";
	}
}

sub addloc
{
	my $locstr = shift;
	$locstr =~ s/\'/\\'/g;
	my $loc = $loc{$locstr} = $nextloc++;
	$locn{$loc} = $locstr;
	return $loc;
}

