#
# DX cluster message strings for output
#
# Each message string will substitute $_[x] positionally. What this means is
# that if you don't like the order in which fields in each message is output then 
# you can change it. Also you can include various globally accessible variables
# in the string if you want. 
#
# Largely because I don't particularly want to have to change all these messages
# in every upgrade I shall attempt to add new field to the END of the list :-)
#
# Copyright (c) 1998 - Dirk Koopman G1TLH
#
# $Id$
#

package DXM;

use strict;
 
use DXVars;
use DXDebug;

my $localfn = "$main::root/local/Messages";
my $fn = "$main::root/perl/Messages";

use vars qw($VERSION $BRANCH);
$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /\d+\.\d+\.(\d+)\.(\d+)/  || (0,0));
$main::build += $VERSION;
$main::branch += $BRANCH;

use vars qw(%msgs);

sub msg
{
	my $lang = shift;
	my $m = shift;
	my $ref = $msgs{$lang};
	my $s = $ref->{$m} if $ref;
	if (!$s && $lang ne 'en') {
		$ref = $msgs{'en'};
		$s = $ref->{$m};
	}
	return "unknown message '$m' in lang '$lang'" if !defined $s;
	my $ans = eval qq{ "$s" };
	warn $@ if $@;
	return $ans;
}

sub load
{
	my $ref = shift;
	if (-e $localfn) {
		do $localfn;
		return ($@) if $@ && ref $ref;
		confess $@ if $@;
		return ();
	}
	do $fn;
	return ($@) if $@ && ref $ref;
	confess $@ if $@;
	return ();
}

sub init
{
	load();
}

1;
