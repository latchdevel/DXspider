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
use Thingy;

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
my $daystart = 0;

sub init
{

}

sub new
{
	my $self = DXChannel::alloc(@_);

	# add this node to the table, the values get filled in later
	my $pkg = shift;
	my $call = shift;
	$main::routeroot->add($call, '5251', Route::here(1)) if $call ne $main::mycall;
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
	
	$self->state('normal');
	$self->{pc50_t} = $main::systime;

	# send info to all logged in thingies
	$self->tell_login('loginn');

	# run a script send the output to the debug file
	my $script = new Script(lc $call) || new Script('node_default');
	$script->run($self) if $script;
}

#
# This is the normal despatcher
#
sub normal
{
	my ($self, $line) = @_;
	my $thing = input($line);
	$thing->queue($self) if $thing;
}

#
# periodic processing
#

sub process
{

	# calc day number
	my $d = (gmtime($main::systime))[3];
	if ($d != $dayno) {
		$dayno = $d;
		$daystart = $main::systime - ($main::systime % 86400);
	}
}

sub disconnect
{
	my $self = shift;
	my $call = $self->call;

	return if $self->{disconnecting}++;
	
	# get rid of any PC16/17/19
#	eph_del_regex("^PC1[679]*$call");

	# do routing stuff, remove me from routing table
	my $node = Route::Node::get($call);
	my @rout;
	if ($node) {
		@rout = $node->del($main::routeroot);
		
		# and all my ephemera as well
		for (@rout) {
			my $c = $_->call;
#			eph_del_regex("^PC1[679].*$c");
		}
	}

	RouteDB::delete_interface($call);
	
	# unbusy and stop and outgoing mail
	my $mref = DXMsg::get_busy($call);
	$mref->stop_msg($call) if $mref;
	
	# broadcast to all other nodes that all the nodes connected to via me are gone
#	$self->route_pc21($main::mycall, undef, @rout) if @rout;

	# remove outstanding pings
#	delete $pings{$call};
	
	# I was the last node visited
    $self->user->node($main::mycall);

	# send info to all logged in thingies
	$self->tell_login('logoutn');

	Log('Aranea', $call . " Disconnected");

	$self->SUPER::disconnect;
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
	my $r = "$mycall,$to," . sprintf('%6X%04X,0', $date, $seqno);
	$r .= ",$from" if $from;
	$seqno++;
	$seqno = 0 if $seqno > 0x0ffff;
	return $r;
}

#
# decode the date time sequence group
#

sub decode_dts
{
	my $dts = shift;
	my ($dt, $seqno) = map {hex} unpack "H6H4", $dts;
	my $secs = $dt & 0x3FFFF;
	$dt >>= 18;
	my $day = $dt >> 1;
	my $ntp = $dt & 1;
	my $t;
	if ($dayno == $day) {
		$t = $daystart + $secs;
	} elsif ($dayno < $day) {
		$t = $daystart + (($day-$dayno) * 86400) + $secs;
	} else {
		$t = $daystart + (($dayno-$day) * 86400) + $secs;
	}
	return ($t, $seqno, $ntp);
}

# subroutines to encode and decode values in lists 
sub tencode
{
	my $s = shift;
	$s =~ s/([\%=|,\'\x00-\x1f\x7f-\xff])/sprintf("%%%02X", ord($1))/eg; 
	$s = "'$s'" if $s =~ / /;
	return $s;
}

sub tdecode
{
	my $s = shift;
	$s =~ s/^'(.*)'$/$1/;
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


sub decode_input
{
	my $self = shift;
	my $line = shift;
	return ('I', $self->{call}, $line);
}

sub input
{
	my $line = shift;
	my ($head, $data) = split /\|/, $line, 2;
	return unless $head && $data;

	my ($origin, $group, $dts, $hop, $user) = split /,/, $head;
	return if DXDupe::check("Ara,$origin,$dts", $dupeage);
	my $err;
	$err .= "incomplete header," unless $origin && defined $group && $dts && defined $hop;
	my ($cmd, $rdata) = split /,/, $data, 2;

	# validate it further
	$err .= "missing cmd or data," unless $cmd && $data;
	$err .= "invalid command ($cmd)," unless $cmd =~ /^[A-Z][A-Z0-9]*$/;
	$err .= "invalid group ($group)," unless $group =~ /^[-A-Z0-9\/:]{2,}$/;

	my $class = 'Thingy::' . ucfirst(lc $cmd);
	my $thing;
	my ($t, $seqno, $ntp) = decode_dts($dts) unless $err;
	$err .= "invalid date/seq," unless $t;
	
	if ($err) {
		chop $err;
		dbg("Aranea input: $err");
	} elsif ($class->can('new')) {
		# create the appropriate Thingy
		$thing = $class->new();

		# reconstitute the header but wth hop increased by one
		$head = join(',', $origin, $group, $dts, ++$hop);
		$head .= ",$user" if $user;
		$thing->{Aranea} = "$head|$data";

		# store useful data
		$thing->{origin} = $origin;
		($thing->{group}, $thing->{touser}) = split /:/, $group, 2;
		$thing->{time} = $t;
		$thing->{user} = $user if $user;
		$thing->{hopsaway} = $hop; 
		
		for (split(/,/, $rdata)) {
			if (/=/) {
				my ($k,$v) = split /=/, $_, 2;
				$thing->{$k} = tdecode($v);
			} else {
				$thing->{$_} = 1;
			}
		}

		# post process the thing, this generally adds on semantic meaning
		# does parameter checking etc. It also adds / prepares the thingy so
		# this is compatible with older protocol and arranges data so
		# that the filtering can still work.
		if ($thing->can('from_Aranea')) {

			# if a thing is ok then return that thing, otherwise return
			# nothing
			$thing = $thing->from_Aranea;
		}
	}
	return $thing;
}

# this is the DXChannel send
# note that this does NOT send out stuff in same way as other DXChannels
# it is just as it comes, no extra bits added (here)
sub send						# this is always later and always data
{
	my $self = shift;
	my $conn = $self->{conn};
	return unless $conn;
	my $call = $self->{call};

	for (@_) {
#		chomp;
        my @lines = split /\n/;
		for (@lines) {
			$conn->send_later($_);
			dbg("-> D $call $_") if isdbg('chan');
		}
	}
	$self->{t} = $main::systime;
}

#
# load of dummies for DXChannel broadcasts
# these will go away in time?
# These are all from PC protocol
#

sub dx_spot
{
	my $self = shift;
	my $line = shift;
	my $isolate = shift;
	my ($filter, $hops);

	if ($self->{spotsfilter}) {
		($filter, $hops) = $self->{spotsfilter}->it(@_);
		return unless $filter;
	}
#	send_prot_line($self, $filter, $hops, $isolate, $line);
}

sub wwv
{
	my $self = shift;
	my $line = shift;
	my $isolate = shift;
	my ($filter, $hops);
	
	if ($self->{wwvfilter}) {
		($filter, $hops) = $self->{wwvfilter}->it(@_);
		return unless $filter;
	}
#	send_prot_line($self, $filter, $hops, $isolate, $line)
}

sub wcy
{
	my $self = shift;
	my $line = shift;
	my $isolate = shift;
	my ($filter, $hops);

	if ($self->{wcyfilter}) {
		($filter, $hops) = $self->{wcyfilter}->it(@_);
		return unless $filter;
	}
#	send_prot_line($self, $filter, $hops, $isolate, $line) if $self->is_clx || $self->is_spider || $self->is_dxnet;
}

sub announce
{
	my $self = shift;
	my $line = shift;
	my $isolate = shift;
	my $to = shift;
	my $target = shift;
	my $text = shift;
	my ($filter, $hops);

	if ($self->{annfilter}) {
		($filter, $hops) = $self->{annfilter}->it(@_);
		return unless $filter;
	}
#	send_prot_line($self, $filter, $hops, $isolate, $line) unless $_[1] eq $main::mycall;
}

sub chat
{
	goto &announce;
}

1;