#
# The new protocol for real at last
#
# $Id$
#
# Copyright (c) 2005 Dirk Koopman G1TLH
#

package Aranea;

use strict;

use DXUtil;
use DXChannel;
use DXUser;
use DXM;
use DXLog;
use DXDebug;
use Filter;
use Time::HiRes qw(gettimeofday tv_interval);
use DXHash;
use Route;
use Route::Node;
use Script;
use Verify;
use DXDupe;

use vars qw($VERSION $BRANCH);
$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /\d+\.\d+\.(\d+)\.(\d+)/  || (0,0));
$main::build += $VERSION;
$main::branch += $BRANCH;

use vars qw(@ISA $ntpflag $dupeage);

@ISA = qw(DXChannel);

$ntpflag = 0;					# should be set in startup if NTP in use
$dupeage = 12*60*60;			# duplicates stored half a day 

my $seqno = 0;
my $dayno = 0;

sub init
{

}

sub new
{
	my $self = DXChannel::alloc(@_);

	# add this node to the table, the values get filled in later
	my $pkg = shift;
	my $call = shift;
	$main::routeroot->add($call, '5000', Route::here(1)) if $call ne $main::mycall;
	$self->{'sort'} = 'W';
	return $self;
}

sub start
{
	my ($self, $line, $sort) = @_;
	my $call = $self->{call};
	my $user = $self->{user};

	# log it
	my $host = $self->{conn}->{peerhost} || "unknown";
	Log('Aranea', "$call connected from $host");
	
	# remember type of connection
	$self->{consort} = $line;
	$self->{outbound} = $sort eq 'O';
	my $priv = $user->priv;
	$priv = $user->priv(1) unless $priv;
	$self->{priv} = $priv;     # other clusters can always be 'normal' users
	$self->{lang} = $user->lang || 'en';
	$self->{consort} = $line;	# save the connection type
	$self->{here} = 1;
	$self->{width} = 80;

	# sort out registration
	$self->{registered} = 1;

	# get the output filters
	$self->{spotsfilter} = Filter::read_in('spots', $call, 0) || Filter::read_in('spots', 'node_default', 0);
	$self->{wwvfilter} = Filter::read_in('wwv', $call, 0) || Filter::read_in('wwv', 'node_default', 0);
	$self->{wcyfilter} = Filter::read_in('wcy', $call, 0) || Filter::read_in('wcy', 'node_default', 0);
	$self->{annfilter} = Filter::read_in('ann', $call, 0) || Filter::read_in('ann', 'node_default', 0) ;
	$self->{routefilter} = Filter::read_in('route', $call, 0) || Filter::read_in('route', 'node_default', 0) unless $self->{isolate} ;


	# get the INPUT filters (these only pertain to Clusters)
	$self->{inspotsfilter} = Filter::read_in('spots', $call, 1) || Filter::read_in('spots', 'node_default', 1);
	$self->{inwwvfilter} = Filter::read_in('wwv', $call, 1) || Filter::read_in('wwv', 'node_default', 1);
	$self->{inwcyfilter} = Filter::read_in('wcy', $call, 1) || Filter::read_in('wcy', 'node_default', 1);
	$self->{inannfilter} = Filter::read_in('ann', $call, 1) || Filter::read_in('ann', 'node_default', 1);
	$self->{inroutefilter} = Filter::read_in('route', $call, 1) || Filter::read_in('route', 'node_default', 1) unless $self->{isolate};
	
	$self->conn->echo(0) if $self->conn->can('echo');
	
	# ping neighbour node stuff
	my $ping = $user->pingint;
	$ping = $DXProt::pingint unless defined $ping;
	$self->{pingint} = $ping;
	$self->{nopings} = $user->nopings || $DXProt::obscount;
	$self->{pingtime} = [ ];
	$self->{pingave} = 999;
	$self->{metric} ||= 100;
	$self->{lastping} = $main::systime;
	
	$self->state('init');
	$self->{pc50_t} = $main::systime;

	# send info to all logged in thingies
	$self->tell_login('loginn');

	# run a script send the output to the debug file
	my $script = new Script(lc $call) || new Script('node_default');
	$script->run($self) if $script;
	$self->send("Hello?");
}

#
# This is the normal despatcher
#
sub normal
{
	my ($self, $line) = @_;

	
}

#
# periodic processing
#

sub process
{

	# calc day number
	$dayno = (gmtime($main::systime))[3];
}

# 
# generate new header (this is a general subroutine, not a method
# because it has to be used before a channel is fully initialised).
#

sub genheader
{
	my $mycall = shift;
	my $to = shift;
	my $from = shift;
	
	my $date = ((($dayno << 1) | $ntpflag) << 18) |  ($main::systime % 86400);
	my $r = "$mycall,$to," . sprintf('%06X%04X,0', $date, $seqno);
	$r .= ",$from" if $from;
	$seqno++;
	$seqno = 0 if $seqno > 0x0ffff;
	return $r;
}

# subroutines to encode and decode values in lists 
sub tencode
{
	my $s = shift;
	$s =~ s/([\%=|,\x00-\x1f\x7f-\xff])/sprintf("%%%02X", ord($1))/eg; 
	return $s;
}

sub tdecode
{
	my $s = shift;
	$s =~ s/\%([0-9A-F][0-9A-F])/chr(hex($1))/eg;
	return $s;
}

sub genmsg
{
	my $thing = shift;
	my $name = shift;
	my $head = genheader($thing->{origin}, 
						 ($thing->{group} || $thing->{touser} || $thing->{tonode}),
						 ($thing->{user} || $thing->{fromuser} || $thing->{fromnode})
						);
	my $data = "$name,";
	while (@_) {
		my $k = lc shift;
		my $v = tencode(shift);
		$data .= "$k=$v,";
	}
	chop $data;
	return "$head|$data";
}

sub input
{
	my $line = shift;
	my ($head, $data) = split /\|/, $line, 2;
	return unless $head && $data;
	my ($origin, $group, $dts, $hop, $user) = split /,/, $head;
	return if DXDupe::add("Ara,$origin,$dts", $dupeage);
	$hop++;
	my ($cmd, $rdata) = split /,/, $data, 2;
	my $class = 'Thingy::' . ucfirst $cmd;
	my $thing;
	
	# create the appropriate Thingy
	if (defined *$class) {
		$thing = $class->new();

		# reconstitute the header but wth hop increased by one
		$head = join(',', $origin, $group, $dts, $hop);
		$head .= ",$user" if $user;
		$thing->{Aranea} = "$head|$data";

		# store useful data
		$thing->{origin} = $origin;
		$thing->{group} = $group;
		$thing->{time} = decode_dts($dts);
		$thing->{user} = $user if $user;
		$thing->{hopsaway} = $hop; 
		
		while (my ($k,$v) = split /,/, $rdata) {
			$thing->{$k} = tdecode($v);
		}
	}
	return $thing;
}

1;
