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
# The NEW INSTRUCTIONS
#
# use the commands accept/spot|ann|wwv|wcy and reject/spot|ann|wwv|wcy
# also show/filter spot|ann|wwv|wcy
#
# The filters live in a directory tree of their own in $main::root/filter
#
# Each type of filter (e.g. spot, wwv) live in a tree of their own so you
# can have different filters for different things for the same callsign.
#


package Filter;

use DXVars;
use DXUtil;
use DXDebug;
use Data::Dumper;

use strict;

use vars qw ($filterbasefn $in);

$filterbasefn = "$main::root/filter";
$in = undef;

# initial filter system
sub init
{

}

sub new
{
	my ($class, $sort, $call, $flag) = @_;
	$flag = ($flag) ? "in_" : "";
	return bless {sort => $sort, name => "$flag$call.pl" }, $class;
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
		$in = undef; 
		my $s = readfilestr($fn);
		my $newin = eval $s;
		dbg('conn', "$@") if $@;
		if ($in) {
			$newin = new('Filter::Old', $sort, $call, $flag);
			$newin->{filter} = $in;
		}
		return $newin;
	}
	return undef;
}

#
# this routine accepts a composite filter with a reject component and then an accept
# the filter returns 0 if an entry is matched by any reject rule and also if any
# accept rule fails otherwise it returns 1
#
# the either set of rules may be missing meaning an implicit 'ok'
#
# reject rules are implicitly 'or' logic (any reject rules which fires kicks it out)
# accept rules are implicitly 'and' logic (all accept rules must pass to indicate a match)
#
# unlike the old system, this is kept as a hash of hashes so that you can
# easily change them by program.
#
# you can have a [any] number of 'filters', they are tried in random order until one matches
#
# an example in machine readable form:-
#   bless ({
#   	name => 'G7BRN.pl',
#   	sort => 'spots',
#   	filter1 => {
#			user_rej => {
#				by_dxcc => 'W,VE',
#			},
#   		reject => {
#   			by_dxcc => [6, 'n', 226,197],
#   		},
#			user_acc => {
#				freq => '0/30000',
#			},
#   		accept => {
#   			freq => [0, 'r', 0, 30000],
#   		},
#   	},
#   	filter2 => {
#			user_acc => {
#				freq => 'vhf',
#				by_zone => '14,15,16',
#			},
#   		accept => {
#   			freq => [0, 'r', 50000,52000,70000,70500,144000,148000],
#   			by_zone => [11, 'n', 14,15,16],
#   		}
#   	},
#   }, 'Filter');
#
# in user commands:-
#
#   clear/spots 1 2
#   accept/spots 1 freq 0/30000
#   reject/spots 1 by_dxcc W,VE
#   accept/spots 2 freq vhf 
#   accept/spots 2 by_zone 14,15,16
#
# no filter no implies filter 1
#
# The field nos are the same as for the 'Old' filters
#
# The user_* fields are there so that the structure can be listed easily
# in human readable form when required. They are not used in the filtering
# process itself.
#
# This defines an HF filter and a VHF filter (as it happens)
# 

sub it
{
	my $self = shift;
	
	my $hops = undef;
	my $filter;
	my $r;
		
	my ($key, $ref, $field, $fieldsort, $comp);
	L1: foreach $key (grep {/^filter/ } keys %$self) {
			my $filter = $self->{$key};
			$r = 0;
			if ($filter->{reject}) {
				foreach $ref (values %{$filter->{reject}}) {
					($field, $fieldsort) = @$ref[0,1];
					my $val = $_[$field];
					if ($fieldsort eq 'n') {
						next L1 if grep $_ == $val, @{$ref}[2..$#$ref];
					} elsif ($fieldsort eq 'r') {
						my $i;
						for ($i = 2; $i < @$ref; $i += 2) {
							next L1 if $val >= $ref->[$i] && $val <= $ref->[$i+1];
						}
					} elsif ($fieldsort eq 'a') {
						next L1  if grep $val =~ m{$_}, @$ref[2..$#$ref];  
					} 
				}
			}
			if ($filter->{accept}) {
				foreach $ref (values %{$filter->{accept}}) {
					($field, $fieldsort) = @$ref[0,1];
					my $val = $_[$field];
					if ($fieldsort eq 'n') {
						next L1 unless grep $_ == $val, @{$ref}[2..$#$ref];
					} elsif ($fieldsort eq 'r') {
						my $i;
						for ($i = 2; $i < @$ref; $i += 2) {
							next L1 unless $val >= $ref->[$i] && $val <= $ref->[$i+1];
						}
					} elsif ($fieldsort eq 'a') {
						next L1 unless grep $val =~ m{$_}, @{$ref}[2..$#$ref];  
					} 
				}
			} 
			$r = 1;
			last;
	}

	# hops are done differently 
	if ($self->{hops}) {
		my $h;
		while (($comp, $ref) = each %{$self->{hops}}) {
			($field, $h) = @$ref;
			if ($_[$field] =~ m{$comp}) {
				$hops = $h;
				last;
			} 
		}		
	}
	return ($r, $hops);
}

# this writes out the filter in a form suitable to be read in by 'read_in'
# It expects a list of references to filter lines
sub write
{
	my $self = shift;
	my $sort = $self->{sort};
	my $fn = $self->{name};
	my $dir = "$filterbasefn/$sort";
	mkdir $dir, 0775 unless -e $dir; 
	my $fh = new IO::File ">$dir/$fn" or return "$dir/$fn $!";
	if ($fh) {
		my $dd = new Data::Dumper([ $self ]);
		$dd->Indent(1);
		$dd->Terse(1);
		$dd->Quotekeys($] < 5.005 ? 1 : 0);
		$fh->print($dd->Dumpxs);
		$fh->close;
	}
	return undef;
}

sub print
{
	my $self = shift;
	return $self->{name};
}

package Filter::Old;

use strict;
use vars qw(@ISA);
@ISA = qw(Filter);

# the OLD instructions!
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

#
# takes the reference to the filter (the first argument) and applies
# it to the subsequent arguments and returns the action specified.
#
sub it
{
	my $self = shift;
	my $filter = $self->{filter};            # this is now a bless ref of course but so what
	
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


1;
__END__
