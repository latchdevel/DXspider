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
use USDB;
use LRU;

use strict;

use vars qw($VERSION $BRANCH);
$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /\d+\.\d+\.(\d+)\.(\d+)/  || (0,0));
$main::build += $VERSION;
$main::branch += $BRANCH;

use vars qw($db %prefix_loc %pre $lru $lrusize $misses $hits $matchtotal);

$db = undef;					# the DB_File handle
%prefix_loc = ();				# the meat of the info
%pre = ();						# the prefix list
$hits = $misses = $matchtotal = 1;		# cache stats
$lrusize = 1000;				# size of prefix LRU cache

sub load
{
	# untie every thing
	if ($db) {
		undef $db;
		untie %pre;
		%pre = ();
		%prefix_loc = ();
		$lru->close if $lru;
		undef $lru;
	}

	# tie the main prefix database
	$db = tie(%pre, "DB_File", undef, O_RDWR|O_CREAT, 0664, $DB_BTREE) or confess "can't tie \%pre ($!)";  
	my $out = $@ if $@;
	do "$main::data/prefix_data.pl" if !$out;
	$out = $@ if $@;
	$lru = LRU->newbase('Prefix', $lrusize);

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
	my $ref;
	my $gotkey = $key;
	return () if $db->seq($gotkey, $ref, R_CURSOR);
	return () if $key ne substr $gotkey, 0, length $key;

	return ($gotkey,  map { $prefix_loc{$_} } split ',', $ref);
}

#
# get the next key that matches, this assumes that you have done a 'get' first
#
# 
sub next
{
	my $key = shift;
	my $ref;
	my $gotkey;
  
	return () if $db->seq($gotkey, $ref, R_NEXT);
	return () if $key ne substr $gotkey, 0, length $key;
  
	return ($gotkey,  map { $prefix_loc{$_} } split ',', $ref);
}

#
# put the key LRU incluing the city state info
#

sub lru_put
{
	my ($call, $ref) = @_;
	my @s = USDB::get($call);
	
	if (@s) {
		# this is deep magic, because this is a reference to static data, it
        # must be copied.
		my $h = { %{$ref->[1]} };
		bless $h, ref $ref->[1];
		$h->{city} = $s[0];
		$h->{state} = $s[1];
		$ref->[1] = $h;
	} else {
		$ref->[1]->{city} = $ref->[1]->{state} = "" unless exists $ref->[1]->{state};
	}
	
	dbg("Prefix::lru_put $call -> ($ref->[1]->{city}, $ref->[1]->{state})") if isdbg('prefix');
	$lru->put($call, $ref);
}

# 
# search for the nearest match of a prefix string (starting
# from the RH end of the string passed)
#

sub matchprefix
{
	my $pref = shift;
	my @partials;

	for (my $i = length $pref; $i; $i--) {
		$matchtotal++;
		my $s = substr($pref, 0, $i);
		push @partials, $s;
		my $p = $lru->get($s);
		if ($p) {
			$hits++;
			if (isdbg('prefix')) {
				my $percent = sprintf "%.1f", $hits * 100 / $misses;
				dbg("Partial Prefix Cache Hit: $s Hits: $hits/$misses of $matchtotal = $percent\%");
			}
			lru_put($_, $p) for @partials;
			return @$p;
		} else {
			$misses++;
			my @out = get($s);
			if (isdbg('prefix')) {
				my $part = $out[0] || "*";
				$part .= '*' unless $part eq '*' || $part eq $s;
				dbg("Partial prefix: $pref $s $part" );
			} 
			if (@out && $out[0] eq $s) {
				return @out;
			} 
		}
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

		# first check if the whole thing succeeds either because it is cached
		# or because it simply is a stored prefix as callsign (or even a prefix)
		$matchtotal++;
		$call =~ s/-\d+$//;		# ignore SSIDs
		my $p = $lru->get($call);
		my @nout;
		if ($p) {
			$hits++;
			if (isdbg('prefix')) {
				my $percent = sprintf "%.1f", $hits * 100 / $misses;
				dbg("Prefix Cache Hit: $call Hits: $hits/$misses of $matchtotal = $percent\%");
			}
			push @out, @$p;
			next;
		} else {
			
			# is it in the USDB, force a matchprefix to match?
			my @s = USDB::get($call);
			if (@s) {
				@nout = get($call);
				@nout = matchprefix($call) unless @nout;
				$nout[0] = $call if @nout;
			} else {
				@nout =  get($call);
			}

			# now store it
			if (@nout && $nout[0] eq $call) {
				$misses++;
				lru_put($call, \@nout);
				dbg("got exact prefix: $nout[0]") if isdbg('prefix');
				push @out, @nout;
				next;
			}
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
				$misses++;
				lru_put($call, \@nout);
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
					$misses++;
					lru_put($call, \@try);
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
					$misses++;
					lru_put($call, \@try);
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
				dbg("got prefix: $call = $nout[0]") if isdbg('prefix');
				$misses++;
				lru_put($call, \@nout);
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
						$misses++;
						lru_put($call, \@try);
						push @out, @try;
					} else {
						$misses++;
						lru_put($call, \@nout);
						push @out, @nout;
					}
				} else {
					$misses++;
					lru_put($call, \@nout);
					push @out, @nout;
				}
				next LM;
			}
		}

		# we are a pirate!
		@nout = matchprefix('Q');
		$misses++;
		lru_put($call, \@nout);
		push @out, @nout;
	}
	
	if (isdbg('prefixdata')) {
		my $dd = new Data::Dumper([ \@out ], [qw(@out)]);
		dbg($dd->Dumpxs);
	}
	return @out;
}

#
# turn a list of prefixes / dxcc numbers into a list of dxcc/itu/zone numbers
#
# nc = dxcc
# ni = itu
# nz = zone
# ns = state
#

sub to_ciz
{
	my $cmd = shift;
	my @out;
	
	foreach my $v (@_) {
		if ($cmd ne 'ns' && $v =~ /^\d+$/) {	
			push @out, $v unless grep $_ eq $v, @out;
		} else {
			if ($cmd eq 'ns' && $v =~ /^[A-Z][A-Z]$/i) {
				push @out, uc $v unless grep $_ eq uc $v, @out;
			} else {
				my @pre = Prefix::extract($v);
				if (@pre) {
					shift @pre;
					foreach my $p (@pre) {
						my $n = $p->dxcc if $cmd eq 'nc' ;
						$n = $p->itu if $cmd eq 'ni' ;
						$n = $p->cq if $cmd eq 'nz' ;
						$n = $p->state if $cmd eq 'ns';
						push @out, $n unless grep $_ eq $n, @out;
					}
				}
			}			
		}
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
			 state => '0,State',
			 city => '0,City',
			 utcoff => '0,UTC offset',
			 cont => '0,Continent',
			);

sub AUTOLOAD
{
	my $self = shift;
	no strict;
	my $name = $AUTOLOAD;
  
	return if $name =~ /::DESTROY$/;
	$name =~ s/^.*:://o;
  
	confess "Non-existant field '$AUTOLOAD'" if !$valid{$name};
	# this clever line of code creates a subroutine which takes over from autoload
	# from OO Perl - Conway
	*$AUTOLOAD = sub {@_ > 1 ? $_[0]->{$name} = $_[1] : $_[0]->{$name}} ;
	&$AUTOLOAD($self, @_);
}

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
