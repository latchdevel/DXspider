#
# The User/Sysop Filter module
#
# The way this works is that the filter routine is actually
# a predefined function that returns 0 if it is OK and 1 if it
# is not when presented with a list of things.
#
# This set of routines provide a means of maintaining the filter
# scripts which are compiled in when an entity connects.
#
# Copyright (c) 1999 Dirk Koopman G1TLH
#
# $Id$
#
# The INSTRUCTIONS
#
# The filters live in a directory tree of their own in $main::root/filter
#
# Each type of filter (e.g. spot, wwv) live in a tree of their own so you
# can have different filters for different things for the same callsign.
#
# Each filter file has the same structure:-
#
# <some comment>
# @in = (
#      [ action, fieldno, fieldsort, comparison, action data ],
#      ...
# );
#
# The action is usually 1 or 0 but could be any numeric value
#
# The fieldno is the field no in the list of fields that is presented
# to 'Filter::it' 
#
# The fieldsort is the type of field that we are dealing with which 
# currently can be 'a', 'n', 'r' or 'd'. 'a' is alphanumeric, 'n' is 
# numeric, 'r' is ranges of pairs of numeric values and 'd' is default.
#
# Filter::it basically goes thru the list of comparisons from top to
# bottom and when one matches it will return the action and the action data as a list. 
# The fields
# are the element nos of the list that is presented to Filter::it. Element
# 0 is the first field of the list.
#

package Filter;

use DXVars;
use DXUtil;
use DXDebug;

use strict;

use vars qw ($filterbasefn $in);

$filterbasefn = "$main::root/filter";
$in = undef;

# initial filter system
sub init
{

}

#
# takes the reference to the filter (the first argument) and applies
# it to the subsequent arguments and returns the action specified.
#
sub it
{
	my $filter = shift;
	my ($action, $field, $fieldsort, $comp, $actiondata);
	my $ref;

	# default action is 1
	$action = 1;
	$actiondata = "";
	return ($action, $actiondata) if !$filter;

	for $ref (@{$filter}) {
		($action, $field, $fieldsort, $comp, $actiondata) = @{$ref};
		if ($fieldsort eq 'n') {
			my $val = $_[$field];
			return ($action, $actiondata)  if grep $_ == $val, @{$comp};
		} elsif ($fieldsort eq 'r') {
			my $val = $_[$field];
			my $i;
			my @range = @{$comp};
			for ($i = 0; $i < @range; $i += 2) {
				return ($action, $actiondata)  if $val >= $range[$i] && $val <= $range[$i+1];
			}
		} elsif ($fieldsort eq 'a') {
			return ($action, $actiondata)  if $_[$field] =~ m{$comp};
		} else {
			return ($action, $actiondata);      # the default action
		}
	}
}

# this reads in a filter statement and returns it as a list
# 
# The filter is stored in straight perl so that it can be parsed and read
# in with a 'do' statement. The 'do' statement reads the filter into
# @in which is a list of references
#
sub read_in
{
	my ($sort, $call, $flag) = @_;

    # first uppercase
	$flag = ($flag) ? "in_" : "";
	$call = uc $call;
	my $fn = "$filterbasefn/$sort/$flag$call.pl";

	# otherwise lowercase
	unless (-e $fn) {
		$call = lc $call;
		$fn = "$filterbasefn/$sort/$flag$call.pl";
	}
	
	# load it
	if (-e $fn) {
		do "$fn";
		dbg('conn', "$@") if $@;
		return $in;
	}
	return undef;
}

# this writes out the filter in a form suitable to be read in by 'read_in'
# It expects a list of references to filter lines
sub write_out
{
	my $sort = shift;
	my $call = shift;
	my $fn = "$filterbasefn/$sort";
	
	
	# make the output directory
	mkdir $fn, 0777 unless -e $fn;

	# write out the file
	$fn = "$fn/$call.pl";
	unless (open FILTER, ">$fn") {
		warn "can't open $fn $!" ;
		return;
	}

	my $today = localtime;
	print FILTER "#!/usr/bin/perl
#
# Filter for $call stored $today
#
\$in = [
";

	my $ref;
	for $ref (@_) {
		my ($action, $field, $fieldsort, $comp, $actiondata) = @{$ref};
		print FILTER "\t[ $action, $field, $fieldsort,";
		if ($fieldsort eq 'n' || $fieldsort eq 'r') {
			print FILTER "[ ", join (',', $comp), " ],";
		} elsif ($fieldsort eq 'a') {
			my $f = $comp;
	        print FILTER "'$f'";
		}
		print FILTER " ],\n";
	}
	print FILTER "];\n";
	close FILTER;
}

1;
__END__
