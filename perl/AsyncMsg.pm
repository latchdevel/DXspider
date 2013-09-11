#
# This class is the internal subclass that does various Async connects and
# retreivals of info. Typical uses (and specific support) include http get and
# post.
# 
# This merely starts up a Msg handler (and no DXChannel) ($conn in other words)
# does the GET, parses out the result and the data and then (assuming a positive
# result and that the originating callsign is still online) punts out the data
# to the caller.
#
# It isn't designed to be very clever.
#
# Copyright (c) 2013 - Dirk Koopman G1TLH
#

package AsyncMsg;

use Msg;
use DXDebug;
use DXUtil;
use DXChannel;

use vars qw(@ISA $deftimeout);

@ISA = qw(Msg);
$deftimeout = 15;

my %outstanding;

#
# standard http get handler
#
sub handle_get
{
	my $conn = shift;
	my $msg = shift;

	my $state = $conn->{state};
	
	dbg("asyncmsg: $msg") if isdbg('async');

	# no point in going on if there is no-one wanting the output anymore
	my $dxchan = DXChannel::get($conn->{caller});
	unless ($dxchan) {
		$conn->disconnect;
		return;
	}
	
	if ($state eq 'waitreply') {
		# look at the reply code and decide whether it is a success
		my ($http, $code, $ascii) = $msg =~ m|(HTTP/\d\.\d)\s+(\d+)\s+(.*)|;
		if ($code == 200) {
			# success
			$conn->{state} = 'waitblank';
		} elsif ($code == 302) {
			# redirect
			$conn->{state} = 'waitlocation';
		} else {
			$dxchan->send("$code $ascii");
			$conn->disconnect;
		} 
	} elsif ($state  eq 'waitlocation') {
		my ($path) = $msg =~ m|Location:\s*(.*)|;
		if ($path) {
			my @uri = split m|/+|, $path;
			if ($uri[0] eq 'http:') {
				shift @uri;
				my $host = shift @uri;
				my $newpath = '/' . join('/', @uri);
				$newpath .= '/' if $path =~ m|/$|;
				_getpost(ref $conn, $conn->{asyncsort}, $conn->{caller}, $host, 80, $newpath, @{$conn->{asyncargs}});
			} elsif ($path =~ m|^/|) {
				_getpost(ref $conn, $conn->{asyncsort}, $conn->{caller}, $conn->{peerhost}, $conn->{peerport}, $path,
						 @{$conn->{asyncargs}});
			}
			delete $conn->{on_disconnect};
			$conn->disconnect;
		}
	} elsif ($state eq 'waitblank') {
		unless ($msg) {
			$conn->{state} = 'indata';
		}
	} elsif ($conn->{state} eq 'indata') {
		if (my $filter = $conn->{filter}) {
			no strict 'refs';
			# this will crash if the command has been redefined and the filter is a
			# function defined there whilst the request is in flight,
			# but this isn't exactly likely in a production environment.
			$filter->($conn, $msg, $dxchan);
		} else {
			my $prefix = $conn->{prefix} || '';
			$dxchan->send("$prefix$msg");
		}
	}
}

# 
# simple raw handler
#
# Just outputs everything
#
sub handle_raw
{
	my $conn = shift;
	my $msg = shift;

	# no point in going on if there is no-one wanting the output anymore
	my $dxchan = DXChannel::get($conn->{caller});
	unless ($dxchan) {
		$conn->disconnect;
		return;
	}

	# send out the data
	my $prefix = $conn->{prefix} || '';
	$dxchan->send("$prefix$msg");
}

sub new 
{
	my $pkg = shift;
	my $call = shift;
	my $handler = shift;
	
	my $conn = $pkg->SUPER::new($handler);
	$conn->{caller} = ref $call ? $call->call : $call;

	# make it persistent
	$outstanding{$conn} = $conn;
	
	return $conn;
}

# This does a http get on a path on a host and
# returns the result (through an optional filter)
#
# expects to be called something like from a cmd.pl file:
#
# AsyncMsg->get($self, <host>, <port>, <path>, [<key=>value>...]
# 
# Standard key => value pairs are:
#
# filter => CODE ref (e.g. sub { ... })
# prefix => <string>                 prefix output with this string
#
# Anything else is taken and sent as (extra) http header stuff e.g:
#
# 'User-Agent' => qq{DXSpider;$main::version;$main::build;$^O}
# 'Content-Type' => q{text/xml; charset=utf-8}
# 'Content-Length' => $lth
#
# Host: is always set to the name of the host (unless overridden)
# User-Agent: is set to default above (unless overridden)
#
sub _getpost
{
	my $pkg = shift;
	my $sort = shift;
	my $call = shift;
	my $host = shift;
	my $port = shift;
	my $path = shift;
	my %args = @_;
	

	my $conn = $pkg->new($call, \&handle_get);
	$conn->{asyncargs} = [@_];
	$conn->{state} = 'waitreply';
	$conn->{filter} = delete $args{filter} if exists $args{filter};
	$conn->{prefix} = delete $args{prefix} if exists $args{prefix};
	$conn->{on_disconnect} = delete $args{on_disc} || delete $args{on_disconnect};
	$conn->{path} = $path;
	$conn->{asyncsort} = $sort;
	
	$r = $conn->connect($host, $port);
	if ($r) {
		dbg("Sending '$sort $path HTTP/1.0'") if isdbg('async');
		$conn->send_later("$sort $path HTTP/1.0\n");

		my $h = delete $args{Host} || $host;
		my $u = delete $args{'User-Agent'} || "DxSpider;$main::version;$main::build;$^O;$main::mycall"; 
		my $d = delete $args{data};
		
	    $conn->send_later("Host: $h\n");
		$conn->send_later("User-Agent: $u\n");
		while (my ($k,$v) = each %args) {
			$conn->send_later("$k: $v\n");
		}
		$conn->send_later("\n$d") if defined $d;
		$conn->send_later("\n");
	}
	
	return $r ? $conn : undef;
}

sub get
{
	my $pkg = shift;
	_getpost($pkg, "GET", @_);
}

sub post
{
	my $pkg = shift;
	_getpost($pkg, "POST", @_);
}

# do a raw connection
#
# Async->raw($self, <host>, <port>, [handler => CODE ref], [prefix => <string>]);
#
# With no handler defined, everything sent by the connection will be sent to
# the caller.
#
# One can send stuff out on the connection by doing a standard "$conn->send_later(...)" 
# inside the (custom) handler.

sub raw
{
	my $pkg = shift;
	my $call = shift;
	my $host = shift;
	my $port = shift;

	my %args = @_;

	my $handler = delete $args{handler} || \&handle_raw;
	my $conn = $pkg->new($call, $handler);
	$conn->{prefix} = delete $args{prefix} if exists $args{prefix};
	$r = $conn->connect($host, $port);
	return $r ? $conn : undef;
}

sub connect
{
	my $conn = shift;
	my $host = shift;
	my $port = shift;
	
	# start a connection
	my $r = $conn->SUPER::connect($host, $port);
	if ($r) {
		dbg("AsyncMsg: Connected $conn->{cnum} to $host $port") if isdbg('async');
	} else {
		dbg("AsyncMsg: ***Connect $conn->{cnum} Failed to $host $port $!") if isdbg('async');
	}
	
	return $r;
}

sub disconnect
{
	my $conn = shift;

	if (my $ondisc = $conn->{on_disconnect}) {
		my $dxchan = DXChannel::get($conn->{caller});
		if ($dxchan) {
			no strict 'refs';
			$ondisc->($conn, $dxchan)
		}
	}
	delete $outstanding{$conn};
	$conn->SUPER::disconnect;
}

sub DESTROY
{
	my $conn = shift;
	delete $outstanding{$conn};
	$conn->SUPER::DESTROY;
}

1;

