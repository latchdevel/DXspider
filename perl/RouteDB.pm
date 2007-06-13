# This module is used to keep a list of where things come from
#
# all interfaces add/update entries in here to allow casual
# routing to occur.
# 
# It is up to the protocol handlers in here to make sure that 
# this information makes sense. 
#
# This is (for now) just an adjunct to the normal routing
# and is experimental. It will override filtering for
# things that are explicitly routed (pings, talks and
# such like).
#
# Copyright (c) 2004 Dirk Koopman G1TLH
#
# $Id$
# 

package RouteDB;

use DXDebug;
use DXChannel;
use DXUtil;
use Prefix;

use strict;

use vars qw(%list %valid $default);


%list = ();
$default = 99;					# the number of hops to use if we don't know
%valid = (
		  call => "0,Callsign",
		  item => "0,Interfaces,parray",
		  t => '0,Last Seen,atime',
		  hops => '0,Hops',
		  count => '0,Times Seen',
		 );

sub new
{
	my $pkg = shift;
	my $call = shift;
	return bless {call => $call, list => {}}, (ref $pkg || $pkg);
}

# get the best one
sub get
{
	my @out = _sorted(shift);
	return @out ? $out[0]->{call} : undef;
}

# get all of them in sorted order
sub get_all
{
	my @out = _sorted(shift);
	return @out ? map { $_->{call} } @out : ();
}

# get them all, sorted into reverse occurance order (latest first)
# with the smallest hops
sub _sorted
{
	my $call = shift;
	my $ref = $list{$call};
	return () unless $ref;
	return sort {
		if ($a->{hops} == $b->{hops}) {
			$b->{t} <=> $a->{t};
		} else {
			$a->{hops} <=> $b->{hops};
		} 
	} values %{$ref->{item}};
}


# add or update this call on this interface
#
# RouteDB::update($call, $interface, $hops, time);
#
sub update
{
	my $call = shift;
	my $interface = shift;
	my $hops = shift || $default;
	my $ref = $list{$call} || RouteDB->new($call);
	my $iref = $ref->{item}->{$interface} ||= RouteDB::Item->new($interface, $hops);
	$iref->{count}++;
	$iref->{hops} = $hops if $hops < $iref->{hops};
	$iref->{t} = shift || $main::systime;
	$ref->{item}->{$interface} ||= $iref;
	$list{$call} ||= $ref;
}

sub delete
{
	my $call = shift;
	my $interface = shift;
	my $ref = $list{$call};
	delete $ref->{item}->{$interface} if $ref;
}

sub delete_interface
{
	my $interface = shift;
	foreach my $ref (values %list) {
		delete $ref->{item}->{$interface};
	}
}

#
# generic AUTOLOAD for accessors
#
sub AUTOLOAD
{
	no strict;
	my $name = $AUTOLOAD;
	return if $name =~ /::DESTROY$/;
	$name =~ s/^.*:://o;
  
	confess "Non-existant field '$AUTOLOAD'" if !$valid{$name};

	# this clever line of code creates a subroutine which takes over from autoload
	# from OO Perl - Conway
	*{$AUTOLOAD} = sub {@_ > 1 ? $_[0]->{$name} = $_[1] : $_[0]->{$name}};
       goto &$AUTOLOAD;

}

package RouteDB::Item;

use vars qw(@ISA);
@ISA = qw(RouteDB);

sub new
{
	my $pkg = shift;
	my $call = shift;
	my $hops = shift || $RouteDB::default;
	return bless {call => $call, hops => $hops}, (ref $pkg || $pkg);
}

1;
