#!/usr/bin/env perl
# a program to create a prefix file from a wpxloc.raw file
#
# Copyright (c) - Dirk Koopman G1TLH
#
#
#

use 5.10.1;

# search local then perl directories
BEGIN {
	# root of directory tree for this system
	$root = "/spider"; 
	$root = $ENV{'DXSPIDER_ROOT'} if $ENV{'DXSPIDER_ROOT'};

	mkdir "$root/local_data", 02777 unless -d "$root/local_data";

	unshift @INC, "$root/perl";	# this IS the right way round!
	unshift @INC, "$root/local";
}

use DXVars;
use SysVar;

use Data::Dumper;
use DXUtil;
use DXBearing;

use strict;

my %loc = ();						# the location unique hash
my $nextloc = 1;					# the next location number
my %locn = ();						# the inverse of the above
my %pre = ();						# the prefix hash
my %pren = ();						# the inverse

my $prefix;
my $system;

if (@ARGV && $ARGV[0] =~ /^-?-?syst?e?m?$/) {
	$prefix = $main::data;
	++$system;
	shift;
	say "create_prefix.pl: creating SYSTEM prefix files";	
} else {
	$prefix = $main::local_data;
	say "create_prefix.pl: creating LOCAL prefix files";	
}

my $ifn;

$ifn = $system ? "$main::data/wpxloc.raw" : "$prefix/wpxloc.raw";
unless (open (IN, $ifn)) {
	$ifn = "$main::data/wpxloc.raw";
	open(IN, $ifn) or die "can't open $ifn ($!)";
}

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

# now open the cty.dat file if it is there
my $r;
$ifn = $system ? "$main::data/cty.dat" : "$prefix/cty.dat";
unless ($r = open (IN, $ifn)) {
	$ifn = "$main::data/cty.dat";
	$r = open(IN, $ifn);
}

my @f;
my @a;
$line = 0;
if ($r) {
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
				$f[7] =~ s/^\*\s*//;   # remove any preceeding '*' before a callsign
				ct($_, uc $f[7], @a) if @a;
			} else {
				s/,$//;
				push @a, split /\s*,/;
			}
		}
	}
}
close IN;


open(OUT, ">$prefix/prefix_data.pl") or die "Can't open $prefix/prefix_data.pl ($!)";

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
	my $qra = DXBearing::lltoqra($latd, $longd);
	print OUT " name => '$name',";
	print OUT " dxcc => $dxcc,";
	print OUT " itu => $itu,";
	print OUT " cq => $cq,";
	print OUT " utcoff => $utcoff,";
	print OUT " lat => $latd,";
	print OUT " long => $longd";
	print OUT " qra => $qra";
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
			my ($itu) = $a =~ /(\(\d+\))/; $a =~ s/(\(\d+\))//g;
			my ($cq) = $a =~ /(\[\d+\])/; $a =~ s/(\[\d+\])//g;
			my ($lat, $long) = $a =~ m{(<[-+\d.]+/[-+\d.]+>)}; $a =~ s{(<[-+\d.]+/[-+\d.]+>)}{}g;
			my ($cont) = $a =~ /(\{[A-Z]{2}\})/; $a =~ s/(\{[A-Z]{2}\})//g;

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

