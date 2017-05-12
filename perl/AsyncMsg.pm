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

	my $state = $conn->{_asstate};
	
	dbg("AsyncMsg: $state $msg") if isdbg('async');

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
			$conn->{_asstate} = 'waitblank';
		} elsif ($code == 302) {
			# redirect
			$conn->{_asstate} = 'waitlocation';
		} else {
			$dxchan->send("$code $ascii");
			$conn->disconnect;
		} 
	} elsif ($state  eq 'waitlocation') {
		my ($path) = $msg =~ m|Location:\s*(.*)|;
		if ($path) {
			my $newconn;
			my @uri = split m|/+|, $path;
			if ($uri[0] eq 'http:') {
				shift @uri;
				my $host = shift @uri;
				my $newpath = '/' . join('/', @uri);
				$newpath .= '/' if $path =~ m|/$|;
				$newconn = _getpost(ref $conn, $conn->{_assort}, $conn->{caller}, $host, 80, $newpath, @{$conn->{_asargs}});
			} elsif ($path =~ m|^/|) {
				$newconn = _getpost(ref $conn, $conn->{_assort}, $conn->{caller}, $conn->{peerhost}, $conn->{peerport}, $path, @{$conn->{_asargs}});
			}
			if ($newconn) {
				# copy over any elements in $conn that are not in $newconn
				while (my ($k,$v) = each %$conn) {
					dbg("AsyncMsg: $state copying over $k -> \$newconn") if isdbg('async');
					$newconn{$k} = $v unless exists $newconn{$k};
				}
			}
			delete $conn->{on_disconnect};
			$conn->disconnect;
		}
	} elsif ($state eq 'waitblank') {
		unless ($msg) {
			$conn->{_asstate} = 'indata';
		}
	} elsif ($conn->{_asstate} eq 'indata') {
		if (my $filter = $conn->{_asfilter}) {
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
	$conn->{_asargs} = [@_];
	$conn->{_asstate} = 'waitreply';
	$conn->{_asfilter} = delete $args{filter} if exists $args{filter};
	$conn->{prefix} = delete $args{prefix} if exists $args{prefix};
	$conn->{on_disconnect} = delete $args{on_disc} || delete $args{on_disconnect};
	$conn->{path} = $path;
	$conn->{_assort} = $sort;
	
	$r = $conn->connect($host, $port);
	if ($r) {
		_send_later($conn, "$sort $path HTTP/1.1\r\n");

		my $h = delete $args{Host} || $host;
		my $u = delete $args{'User-Agent'} || "DxSpider;$main::version;$main::build;$^O;$main::mycall"; 
		my $d = delete $args{data};
		
	    _send_later($conn, "Host: $h\r\n");
		_send_later($conn, "User-Agent: $u\r\n");
		while (my ($k,$v) = each %args) {
			_send_later($conn, "$k: $v\r\n");
		}
		_send_later($conn, "\r\n$d") if defined $d;
		_send_later($conn, "\r\n");
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

sub _send_later
{
	my $conn = shift;
	my $m = shift;
	
	if (isdbg('async')) {
		my $s = $m;
		$s =~ s/([\%\x00-\x1f\x7f-\xff])/sprintf("%%%02X", ord($1))/eg;
		dbg("AsyncMsg: send $s");
	}
	$conn->send_later($m);
}

sub DESTROY
{
	my $conn = shift;
	delete $outstanding{$conn};
	$conn->SUPER::DESTROY;
}

1;

