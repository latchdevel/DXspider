#
# prefix handling
#
# Copyright (c) - Dirk Koopman G1TLH
#
# $Id$
#

package Prefix;

use IO::File;
use DXVars;
use DB_File;
use Data::Dumper;
use DXDebug;
use DXUtil;


use strict;

use vars qw($VERSION $BRANCH);
$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /\d+\.\d+\.(\d+)\.(\d+)/  || (0,0));
$main::build += $VERSION;
$main::branch += $BRANCH;

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
# search for the nearest match of a prefix string (starting
# from the RH end of the string passed)
#

sub matchprefix
{
	my $pref = shift;

	for (my $i = length $pref; $i; $i--) {
		my $s = substr($pref, 0, $i);
		my @out = get($s);
		if (isdbg('prefix')) {
			my $part = $out[0] || "*";
			$part .= '*' unless $part eq '*' || $part eq $s;
			dbg("Partial prefix: $pref $s $part" );
		} 
		return @out if @out && $out[0] eq $s;
	}
	return ();
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
	my $calls = uc shift;
	my @out;
	my $p;
	my @parts;
	my ($call, $sp, $i);
  
LM:	foreach $call (split /,/, $calls) {
		# first check if the whole thing succeeds
		my @nout = get($call);
		if (@nout && $nout[0] eq $call) {
			dbg("got exact prefix: $nout[0]") if isdbg('prefix');
			push @out, @nout;
			next;
		}

		# now split the call into parts if required
		@parts = ($call =~ '/') ? split('/', $call) : ($call);
		dbg("Parts: $call = " . join(' ', @parts))	if isdbg('prefix');

		# remove any /0-9 /P /A /M /MM /AM suffixes etc
		if (@parts > 1) {
			@parts = grep { !/^\d+$/ && !/^[PABM]$/ && !/^(?:|AM|MM|BCN|JOTA|SIX|WEB|NET|Q\w+)$/; } @parts;

			# can we resolve them by direct lookup
			my $s = join('/', @parts); 
			@nout = get($s);
			if (@nout && $nout[0] eq $s) {
				dbg("got exact multipart prefix: $call $s") if isdbg('prefix');
				push @out, @nout;
				next;
			}
		}
		dbg("Parts now: $call = " . join(' ', @parts))	if isdbg('prefix');
  
		# at this point we should have two or three parts
		# if it is three parts then join the first and last parts together
		# to get an answer

		# first deal with prefix/x00xx/single letter things
		if (@parts == 3 && length $parts[0] <= length $parts[1]) {
			@nout = matchprefix($parts[0]);
			if (@nout) {
				my $s = join('/', $nout[0], $parts[2]);
				my @try = get($s);
				if (@try && $try[0] eq $s) {
					dbg("got 3 part prefix: $call $s") if isdbg('prefix');
					push @out, @try;
					next;
				}
				
				# if the second part is a callsign and the last part is one letter
				if (is_callsign($parts[1]) && length $parts[2] == 1) {
					pop @parts;
				}
			}
		}

		# if it is a two parter 
		if (@parts == 2) {

			# try it as it is as compound, taking the first part as the prefix
			@nout = matchprefix($parts[0]);
			if (@nout) {
				my $s = join('/', $nout[0], $parts[1]);
				my @try = get($s);
				if (@try && $try[0] eq $s) {
					dbg("got 2 part prefix: $call $s") if isdbg('prefix');
					push @out, @try;
					next;
				}
			}
		}

		# remove the problematic /J suffix
		pop @parts if @parts > 1 && $parts[$#parts] eq 'J';

		# single parter
		if (@parts == 1) {
			@nout = matchprefix($parts[0]);
			if (@nout) {
				dbg("got prefix: $call ]") if isdbg('prefix');
				push @out, @nout;
				next;
			}
		}

		# try ALL the parts
        my @checked;
		my $n;
L1:		for ($n = 0; $n < @parts; $n++) {
			my $sp = '';
			my ($k, $i);
			for ($i = $k = 0; $i < @parts; $i++) {
				next if $checked[$i];
				my $p = $parts[$i];
				if (!$sp || length $p < length $sp) {
					dbg("try part: $p") if isdbg('prefix');
					$k = $i;
					$sp = $p;
				}
			}
			$checked[$k] = 1;
			$sp =~ s/-\d+$//;     # remove any SSID
			
			# now start to resolve it from the right hand end
			@nout = matchprefix($sp);
			
			# try and search for it in the descriptions as
			# a whole callsign if it has multiple parts and the output
			# is more two long, this should catch things like
			# FR5DX/T without having to explicitly stick it into
			# the prefix table.
			
			if (@nout) {
				if (@parts > 1) {
					$parts[$k] = $nout[0];
					my $try = join('/', @parts);
					my @try = get($try);
					if (isdbg('prefix')) {
						my $part = $try[0] || "*";
						$part .= '*' unless $part eq '*' || $part eq $try;
						dbg("Compound prefix: $try $part" );
					}
					if (@try && $try eq $try[0]) {
						push @out, @try;
					} else {
						push @out, @nout;
					}
				} else {
					push @out, @nout;
				}
				next LM;
			}
		}

		# we are a pirate!
		push @out, matchprefix('Q');
	}
	
	if (isdbg('prefix')) {
		my $dd = new Data::Dumper([ \@out ], [qw(@out)]);
		dbg($dd->Dumpxs);
	}
	return @out;
}

my %valid = (
			 lat => '0,Latitude,slat',
			 long => '0,Longitude,slong',
			 dxcc => '0,DXCC',
			 name => '0,Name',
			 itu => '0,ITU',
			 cq => '0,CQ',
			 utcoff => '0,UTC offset',
			 cont => '0,Continent',
			);

no strict;
sub AUTOLOAD
{
	my $self = shift;
	my $name = $AUTOLOAD;
  
	return if $name =~ /::DESTROY$/;
	$name =~ s/.*:://o;
  
	confess "Non-existant field '$AUTOLOAD'" if !$valid{$name};
	# this clever line of code creates a subroutine which takes over from autoload
	# from OO Perl - Conway
	*{$AUTOLOAD} = sub {@_ > 1 ? $_[0]->{$name} = $_[1] : $_[0]->{$name}} ;
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
