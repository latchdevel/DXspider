#
# This class is the internal subclass that does the equivalent of a
# GET http://<some site>/<some path> and passes the result back to the caller.
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

package HTTPMsg;

use Msg;
use DXDebug;
use DXUtil;
use DXChannel;

use vars qw(@ISA $deftimeout);

@ISA = qw(Msg);
$deftimeout = 15;

my %outstanding;

sub handle
{
	my $conn = shift;
	my $msg = shift;

	my $state = $conn->{state};
	
	dbg("httpmsg: $msg") if isdbg('http');

	# no point in going on if there is no-one wanting the output anymore
	my $dxchan = DXChannel::get($conn->{caller});
	return unless $dxchan;
	
	if ($state eq 'waitreply') {
		# look at the reply code and decide whether it is a success
		my ($http, $code, $ascii) = $msg =~ m|(HTTP/\d\.\d)\s+(\d+)\s+(.*)|;
		if ($code == 200) {
			# success
			$conn->{state} = 'waitblank';
		} else {
			$dxchan->send("$code $ascii");
			$conn->disconnect;
		} 
	} elsif ($state eq 'waitblank') {
		unless ($msg) {
			$conn->{state} = 'indata';
		}
	} else {
		if (my $filter = $conn->{filter}) {
			no strict 'refs';
			# this will crash if the command has been redefined and the filter is a
			# function defined there whilst the request is in flight,
			# but this isn't exactly likely in a production environment.
			$filter->($conn, $msg, $dxchan);
		} else {
			$dxchan->send($msg);
		}
	}
}

sub get
{
	my $pkg = shift;
	my $call = shift;
	my $host = shift;
	my $port = shift;
	my $path = shift;
	my $filter = shift;
	
	my $conn = $pkg->new(\&handle);
	$conn->{caller} = $call;
	$conn->{state} = 'waitreply';
	$conn->{host} = $host;
	$conn->{port} = $port;
	$conn->{filter} = $filter if $filter;
	
	# make it persistent
	$outstanding{$conn} = $conn;
	
	$r = $conn->connect($host, $port);
	if ($r) {
		dbg("Sending 'GET $path HTTP/1.0'") if isdbg('http');
		$conn->send_later("GET $path HTTP/1.0\nHost: $host\nUser-Agent: DxSpider;$main::version;$main::build;$^O;$main::mycall;$call\n\n");
	} 
	
	return $r;
}

sub connect
{
	my $conn = shift;
	my $host = shift;
	my $port = shift;
	
	# start a connection
	my $r = $conn->SUPER::connect($host, $port);
	if ($r) {
		dbg("HTTPMsg: Connected $conn->{cnum} to $host $port") if isdbg('http');
	} else {
		dbg("HTTPMsg: ***Connect $conn->{cnum} Failed to $host $port $!") if isdbg('http');
	}
	
	return $r;
}

sub disconnect
{
	my $conn = shift;
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

