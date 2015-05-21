#!/usr/bin/env perl
#
# create a version and build id for the project using git ids
#
#
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
my $desc = `git describe --long`;
my ($v, $s, $b, $g) = $desc =~ /^([\d.]+)(?:\.(\d+))?-(\d+)-g([0-9a-f]+)/;
$b++;			# to account for the commit that is about to happen

open F, ">$fn" or die "issue.pl: can't open $fn $!\n";
print F qq(#
# Version information for DXSpider
#
# DO NOT ALTER THIS FILE. It is generated automatically
# and will be overwritten
#

package main;

use vars qw(\$version \$build \$gitversion);

\$version = '$v';
\$build = '$b';
\$gitversion = '$g\[i]';

1;
);

exit(0);
