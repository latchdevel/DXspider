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

# standard filename generator
sub getfn
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
	$fn = undef unless -e $fn;
	return $fn;
}

# this reads in a filter statement and returns it as a list
# 
# The filter is stored in straight perl so that it can be parsed and read
# in with a 'do' statement. The 'do' statement reads the filter into
# @in which is a list of references
#
sub compile
{
	my $self = shift;
	my $fname = shift;
	my $ar = shift;
	my $ref = $self->{$fname};
	my $rr;
	
	if ($ref->{$ar} && exists $ref->{$ar}->{asc}) {
		$ref->{$ar}->{code} = eval "sub { my \$r=shift; return $ref->{$ar}->{asc}; }" ;
		if ($@) {
			my $sort = $ref->{sort};
			my $name = $ref->{name};
			dbg("Error compiling $ar $sort $name: $@") if isdbg('err');
			Log('err', "Error compiling $ar $sort $name: $@");
		}
		$rr = $@;
	}
	return $rr;
}

sub read_in
{
	my ($sort, $call, $flag) = @_;
	my $fn;
	
	# load it
	if ($fn = getfn($sort, $call, $flag)) {
		$in = undef; 
		my $s = readfilestr($fn);
		my $newin = eval $s;
		dbg($@) if $@;
		if ($in) {
			$newin = new('Filter::Old', $sort, $call, $flag);
			$newin->{filter} = $in;
		} else {
			my $filter;
			my $key;
			foreach $key ($newin->getfilkeys) {
				$newin->compile($key, 'reject');
				$newin->compile($key, 'accept');
			}
		}
		return $newin;
	}
	return undef;
}

sub getfilters
{
	my $self = shift;
	my @out;
	my $key;
	foreach $key (grep {/^filter/ } keys %$self) {
		push @out, $self->{$key};
	}
	return @out;
}

sub getfilkeys
{
	my $self = shift;
	return grep {/^filter/ } keys %$self;
}

#
# This routine accepts a composite filter with a reject rule and then an accept rule.
#
# The filter returns 0 if an entry is matched by any reject rule and also if any
# accept rule fails otherwise it returns 1
#
# Either set of rules may be missing meaning an implicit 'opposite' ie if it
# a reject then ok else if an accept then not ok.
#
# you can set a default with either an accept/xxxx all or reject/xxxx all
#
# Unlike the old system, this is kept as a hash of hashes so that you can
# easily change them by program.
#
# You can have 10 filter lines (0->9), they are tried in order until 
# one matches
#
# There is a parser that takes a Filter::Cmd object which describes all the possible
# things you can filter on and then converts that to a bit of perl which is compiled
# and stored as a function.
#
# The result of this is that in theory you can put together an arbritrarily complex 
# expression involving the things you can filter on including 'and' 'or' 'not' and 
# 'brackets'.
#
# eg:-
#
# accept/spots hf and by_zone 14,15,16 and not by pa,on
#  
# accept/spots freq 0/30000 and by_zone 4,5
# 
# accept/spots 2 vhf and (by_zone 14,15,16 or call_dxcc 61) 
#
# no filter no implies filter 1
#
# The field nos are the same as for the 'Old' filters
#
# 

sub it
{
	my $self = shift;
	
	my $filter;
	my @keys = sort $self->getfilkeys;
	my $key;
	my $type = 'Dunno';
	my $asc = '?';
	
	my $r = @keys > 0 ? 0 : 1;
	foreach $key (@keys) {
		$filter = $self->{$key};
		if ($filter->{reject} && exists $filter->{reject}->{code}) {
			$type = 'reject';
			$asc = $filter->{reject}->{user};
			if (&{$filter->{reject}->{code}}(\@_)) {
				$r = 0;
				last;
			} else {
				$r = 1;
			}		
		}
		if ($filter->{accept} && exists $filter->{accept}->{code}) {
			$type = 'accept';
			$asc = $filter->{accept}->{user};
			if (&{$filter->{accept}->{code}}(\@_)) {
				$r = 1;
				last;
			} else {
				$r = 0;
			}			
		} 
	}

	# hops are done differently (simply) 
	my $hops = $self->{hops} if exists $self->{hops};

	if (isdbg('filter')) {
		my $args = join '\',\'', @_;
		my $true = $r ? "OK" : "REJ";
		my $sort = $self->{sort};
		$hops ||= "none";
		dbg("Filter: $type/$sort with $asc on '$args': $true hops: $hops") if isdbg('filter');
	}
	return ($r, $hops);
}

# this writes out the filter in a form suitable to be read in by 'read_in'
# It expects a list of references to filter lines
sub write
{
	my $self = shift;
	my $sort = $self->{sort};
	my $name = $self->{name};
	my $dir = "$filterbasefn/$sort";
	my $fn = "$dir/$name";

	mkdir $dir, 0775 unless -e $dir; 
    rename $fn, "$fn.o" if -e $fn;
	my $fh = new IO::File ">$fn";
	if ($fh) {
		my $dd = new Data::Dumper([ $self ]);
		$dd->Indent(1);
		$dd->Terse(1);
		$dd->Quotekeys($] < 5.005 ? 1 : 0);
		$fh->print($dd->Dumpxs);
		$fh->close;
	} else {
		rename "$fn.o", $fn if -e "$fn.o";
		return "$fn $!";
	}
	return undef;
}

sub print
{
	my $self = shift;
	my $name = shift || $self->{name};
	my $sort = shift || $self->{sort};
	my $flag = shift || "";
	my @out;
	$name =~ s/.pl$//;
	
	push @out, join(' ',  $name , ':', $sort, $flag);
	my $filter;
	my $key;
	foreach $key (sort $self->getfilkeys) {
		my $filter = $self->{$key};
		if (exists $filter->{reject} && exists $filter->{reject}->{user}) {
			push @out, ' ' . join(' ', $key, 'reject', $filter->{reject}->{user});
		}
		if (exists $filter->{accept} && exists $filter->{accept}->{user}) {
			push @out, ' ' . join(' ', $key, 'accept', $filter->{accept}->{user});
		} 
	}
	return @out;
}

sub install
{
	my $self = shift;
	my $remove = shift;
	my $name = uc $self->{name};
	my $sort = $self->{sort};
	my $in = "";
	$in = "in" if $name =~ s/^IN_//;
	$name =~ s/.PL$//;
		
	my $dxchan = DXChannel->get($name);
	if ($dxchan) {
		my $n = "$in$sort" . "filter";
		$dxchan->$n($remove ? undef : $self);
	}
}

sub delete
{
	my ($sort, $call, $flag, $fno) = @_;
	
	# look for the file
	my $fn = getfn($sort, $call, $flag);
	my $filter = read_in($sort, $call, $flag);
	if ($filter) {
		if ($fno eq 'all') {
			my $key;
			foreach $key ($filter->getfilkeys) {
				delete $filter->{$key};
			}
		} elsif (exists $filter->{"filter$fno"}) {
			delete $filter->{"filter$fno"}; 
		}
		
		# get rid 
		if ($filter->{hops} || $filter->getfilkeys) {
			$filter->install;
			$filter->write;
		} else {
			$filter->install(1);
			unlink $fn;
		}
	}
}

package Filter::Cmd;

use strict;
use DXVars;
use DXUtil;
use DXDebug;
use vars qw(@ISA);
@ISA = qw(Filter);

# the general purpose command processor
# this is called as a subroutine not as a method
sub parse
{
	my ($self, $dxchan, $sort, $line) = @_;
	my $ntoken = 0;
	my $fno = 1;
	my $filter;
	my ($flag, $call);
	my $s;
	my $user;
	
	# check the line for non legal characters
	return ('ill', $dxchan->msg('e19')) if $line =~ /[^\s\w,_\-\*\/\(\)]/;
	
	# add some spaces for ease of parsing
	$line =~ s/([\(\)])/ $1 /g;
	$line = lc $line;
	
	my @f = split /\s+/, $line;
	my $conj = ' && ';
	my $not = "";
	while (@f) {
		if ($ntoken == 0) {
			
			if (@f && $dxchan->priv >= 8 && ((is_callsign(uc $f[0]) && DXUser->get(uc $f[0])) || $f[0] =~ /(?:node|user)_default/)) {
				$call = shift @f;
				if ($f[0] eq 'input') {
					shift @f;
					$flag++;
				}
			} else {
				$call = $dxchan->call;
			}

			if (@f && $f[0] =~ /^\d$/) {
				$fno = shift @f;
			}

			$filter = Filter::read_in($sort, $call, $flag);
			$filter = Filter->new($sort, $call, $flag) if !$filter || $filter->isa('Filter::Old');
			
			$ntoken++;
			next;
		}

		# do the rest of the filter tokens
		if (@f) {
			my $tok = shift @f;
			if ($tok eq '(') {
				if ($s) {
					$s .= $conj;
					$user .= $conj;
					$conj = "";
				}
				if ($not) {
					$s .= $not;
					$user .= $not;
					$not = "";
				}
				$s .= $tok;
				$user .= $tok;
				next;
			} elsif ($tok eq ')') {
				$conj = ' && ';
				$not ="";
				$s .= $tok;
				$user .= $tok;
				next;
			} elsif ($tok eq 'all') {
				$s .= '1';
				$user .= $tok;
				last;
			} elsif ($tok eq 'or') {
				$conj = ' || ' if $conj ne ' || ';
				next;
			} elsif ($tok eq 'and') {
				$conj = ' && ' if $conj ne ' && ';
				next;
			} elsif ($tok eq 'not' || $tok eq '!') {
				$not = '!';
				next;
			}
			if (@f) {
				my $val = shift @f;
				my @val = split /,/, $val;

				if ($s) {
					$s .= $conj ;
					$s .= $not;
					$user .= $conj;
					$user .= $not;
					$conj = ' && ';
					$not = "";
				}
				$user .= "$tok $val";
				
				my $fref;
				my $found;
				foreach $fref (@$self) {
					
					if ($fref->[0] eq $tok) {
						if ($fref->[4]) {
							my @nval;
							for (@val) {
								push @nval, split(',', &{$fref->[4]}($dxchan, $_));
							}
							@val = @nval;
						}
						if ($fref->[1] eq 'a') {
							my @t;
							for (@val) {
								s/\*//g;
								push @t, "\$r->[$fref->[2]]=~/$_/i";
							}
							$s .= "(" . join(' || ', @t) . ")";
						} elsif ($fref->[1] eq 'c') {
							my @t;
							for (@val) {
								s/\*//g;
								push @t, "\$r->[$fref->[2]]=~/^\U$_/";
							}
							$s .= "(" . join(' || ', @t) . ")";
						} elsif ($fref->[1] eq 'n') {
							my @t;
							for (@val) {
								return ('num', $dxchan->msg('e21', $_)) unless /^\d+$/;
								push @t, "\$r->[$fref->[2]]==$_";
							}
							$s .= "(" . join(' || ', @t) . ")";
						} elsif ($fref->[1] eq 'r') {
							my @t;
							for (@val) {
								return ('range', $dxchan->msg('e23', $_)) unless /^(\d+)\/(\d+)$/;
								push @t, "(\$r->[$fref->[2]]>=$1 && \$r->[$fref->[2]]<=$2)";
							}
							$s .= "(" . join(' || ', @t) . ")";
						} elsif ($fref->[1] eq 't') {
							my @t;
							for (@val) {
								s/\*//g;
								push @t, "\$r->[$fref->[2]]=~/$_/i";
							}
							$s .= "(" . join(' || ', @t) . ")";
						} else {
							confess("invalid letter $fref->[1]");
						}
						++$found;
						last;
					}
				}
				return ('unknown', $dxchan->msg('e20', $tok)) unless $found;
			} else {
				return ('no', $dxchan->msg('filter2', $tok));
			}
		}
		
	}

	# tidy up the user string
	$user =~ s/\&\&/ and /g;
	$user =~ s/\|\|/ or /g;
	$user =~ s/\!/ not /g;
	$user =~ s/\s+/ /g;
	
	return (0, $filter, $fno, $user, "$s");
}

# a filter accept/reject command
sub cmd
{
	my ($self, $dxchan, $sort, $type, $line) = @_;
	
	return $dxchan->msg('filter5') unless $line;

	my ($r, $filter, $fno, $user, $s) = $self->parse($dxchan, $sort, $line);
	return (1,$filter) if $r;

	my $fn = "filter$fno";

	$filter->{$fn} = {} unless exists $filter->{$fn};
	$filter->{$fn}->{$type} = {} unless exists $filter->{$fn}->{$type};

	$filter->{$fn}->{$type}->{user} = $user;
	$filter->{$fn}->{$type}->{asc} = $s;
	$r = $filter->compile($fn, $type);
	return (1,$r) if $r;
	
	$r = $filter->write;
	return (1,$r) if $r;
	
	$filter->install;

    return (0, $filter, $fno);
}

package Filter::Old;

use strict;
use DXVars;
use DXUtil;
use DXDebug;
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

sub print
{
	my $self = shift;
	my $call = shift;
	my $sort = shift;
	my $flag = shift || "";
	return "$call: Old Style Filter $flag $sort";
}

1;
__END__
