#
# prefix handling
#
# Copyright (c) - Dirk Koopman G1TLH
#
# $Id$
#

package Prefix;

use IO::File;
use Carp;
use DXVars;
use DB_File;
use Data::Dumper;
use Carp;

use strict;
use vars qw($db  %prefix_loc %pre);

$db = undef;					# the DB_File handle
%prefix_loc = ();				# the meat of the info
%pre = ();						# the prefix list

sub load
{
	if ($db) {
		undef $db;
		untie %pre;
		%pre = ();
		%prefix_loc = ();
	}
	$db = tie(%pre, "DB_File", undef, O_RDWR|O_CREAT, 0666, $DB_BTREE) or confess "can't tie \%pre ($!)";  
	my $out = $@ if $@;
	do "$main::data/prefix_data.pl" if !$out;
	$out = $@ if $@;
	#  print Data::Dumper->Dump([\%pre, \%prefix_loc], [qw(pre prefix_loc)]);
	return $out;
}

sub store
{
	my ($k, $l);
	my $fh = new IO::File;
	my $fn = "$main::data/prefix_data.pl";
  
	confess "Prefix system not started" if !$db;
  
	# save versions!
	rename "$fn.oooo", "$fn.ooooo" if -e "$fn.oooo";
	rename "$fn.ooo", "$fn.oooo" if -e "$fn.ooo";
	rename "$fn.oo", "$fn.ooo" if -e "$fn.oo";
	rename "$fn.o", "$fn.oo" if -e "$fn.o";
	rename "$fn", "$fn.o" if -e "$fn";
  
	$fh->open(">$fn") or die "Can't open $fn ($!)";

	# prefix location data
	$fh->print("%prefix_loc = (\n");
	foreach $l (sort {$a <=> $b} keys %prefix_loc) {
		my $r = $prefix_loc{$l};
		$fh->printf("   $l => bless( { name => '%s', dxcc => %d, itu => %d, utcoff => %d, lat => %f, long => %f }, 'Prefix'),\n",
					$r->{name}, $r->{dxcc}, $r->{itu}, $r->{cq}, $r->{utcoff}, $r->{lat}, $r->{long});
	}
	$fh->print(");\n\n");

	# prefix data
	$fh->print("%pre = (\n");
	foreach $k (sort keys %pre) {
		$fh->print("   '$k' => [");
		my @list = @{$pre{$k}};
		my $l;
		my $str;
		foreach $l (@list) {
			$str .= " $l,";
		}
		chop $str;  
		$fh->print("$str ],\n");
	}
	$fh->print(");\n");
	undef $fh;
	untie %pre; 
}

# what you get is a list that looks like:-
# 
# prefix => @list of blessed references to prefix_locs 
#
# This routine will only do what you ask for, if you wish to be intelligent
# then that is YOUR problem!
#
sub get
{
	my $key = shift;
	my @out;
	my @outref;
	my $ref;
	my $gotkey;
  
	$gotkey = $key;
	return () if $db->seq($gotkey, $ref, R_CURSOR);
	return () if $key ne substr $gotkey, 0, length $key;

	@outref = map { $prefix_loc{$_} } split ',', $ref;
	return ($gotkey, @outref);
}

#
# get the next key that matches, this assumes that you have done a 'get' first
#
# 
sub next
{
	my $key = shift;
	my @out;
	my @outref;
	my $ref;
	my $gotkey;
  
	return () if $db->seq($gotkey, $ref, R_NEXT);
	return () if $key ne substr $gotkey, 0, length $key;
  
	@outref = map { $prefix_loc{$_} } split ',', $ref;
	return ($gotkey, @outref);
}

#
# extract a 'prefix' from a callsign, in other words the largest entity that will
# obtain a result from the prefix table.
#
# This is done by repeated probing, callsigns of the type VO1/G1TLH or
# G1TLH/VO1 (should) return VO1
#

sub extract
{
	my $call = uc shift;
	my @out;
	my @nout;
	my $p;
	my @parts;
	my ($sp, $i);
  
	# first check if the whole thing succeeds
	@out = get($call);
	return @out if @out > 0 && $out[0] eq $call;
  
	# now split the call into parts if required
	@parts = ($call =~ '/') ? split('/', $call) : ($call);

	# remove any /0-9 /P /A /M /MM /AM suffixes etc
	if (@parts > 1) {
		$p = $parts[$#parts];
		pop @parts if $p =~ /^(\d+|[PABM]|AM|MM|BCN|SIX|Q\w+)$/o;
		$p = $parts[$#parts];
		pop @parts if $p =~ /^(\d+|[PABM]|AM|MM|BCN|SIX|Q\w+)$/o;
  
		# can we resolve them by direct lookup
		foreach $p (@parts) {
			@out = get($p);
			return @out if @out > 0 && $out[0] eq $call;
		}
	}
  
	# which is the shortest part (first if equal)?
	$sp = $parts[0];
	foreach $p (@parts) {
		$sp = $p if length $sp > length $p;
	}
	# now start to resolve it from the left hand end
	for (@out = (), $i = 1; $i <= length $sp; ++$i) {
		@nout = get(substr($sp, 0, $i));
		last if @nout > 0 && $nout[0] gt $sp;
		last if @nout == 0;
		@out = @nout;
	}
  
	# not found
	return (@out > 0) ? @out : ();
}

my %valid = (
			 lat => '0,Latitude,slat',
			 long => '0,Longitude,slong',
			 dxcc => '0,DXCC',
			 name => '0,Name',
			 itu => '0,ITU',
			 cq => '0,CQ',
			 utcoff => '0,UTC offset',
			);

no strict;
sub AUTOLOAD
{
	my $self = shift;
	my $name = $AUTOLOAD;
  
	return if $name =~ /::DESTROY$/;
	$name =~ s/.*:://o;
  
	confess "Non-existant field '$AUTOLOAD'" if !$valid{$name};
	if (@_) {
		$self->{$name} = shift;
	}
	return $self->{$name};
}
use strict;

#
# return a prompt for a field
#

sub field_prompt
{ 
	my ($self, $ele) = @_;
	return $valid{$ele};
}
1;

__END__
