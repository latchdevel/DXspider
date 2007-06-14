#!/usr/bin/perl
#
# create a version and build id for the project using git ids
#
# $Id$
#
# Copyright (c) 2007 Dirk Koopman, G1TLH
#

# Determine the correct place to put stuff
BEGIN {
	# root of directory tree for this system
	$root = "/spider";
	$root = $ENV{'DXSPIDER_ROOT'} if $ENV{'DXSPIDER_ROOT'};
}

use strict;

use vars qw($root);
my $fn = "$root/perl/Version.pm";
my $desc = `git-describe`;
my ($v, $b) = $desc =~ /^([\d.]+)-(\d+)-/;
$b++;			# to account for the commit that is about to happen

open F, ">$fn" or die "issue.pl: can't open $fn $!\n";
print F qq(#
# Version information for DXSpider
#
# DO NOT ALTER THIS FILE. It is generated automatically
# and will be overwritten
#

package main;

use vars qw(\$version \$build);

\$version = '$v';
\$build = '$b';

1;
);
