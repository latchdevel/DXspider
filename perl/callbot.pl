#!/usr/bin/env perl
#
# an attempt at producing a general purpose 'bot' for going and getting
# things orf the web and presenting them to user in a form they want
#
# This program uses LWP::Parallel::UserAgent to do its business
#
# each sub bot has the same structure and calling interface, but the actual
# input and output data formats are completely arbitrary
#
# Copyright (c) 1999 - Dirk Koopman, Tobit Computer Co Ltd
#
#
#

package main;

BEGIN {
	umask 002;
	
	# root of directory tree for this system
	$root = "/spider"; 
	$root = $ENV{'DXSPIDER_ROOT'} if $ENV{'DXSPIDER_ROOT'};
	
	unshift @INC, "$root/perl";	# this IS the right way round!
	unshift @INC, "$root/local";
}

use strict;
use ForkingServer;
require LWP::Parallel::UserAgent;
use HTTP::Request;
use URI::Escape;
use IO::File;
use Carp;
use Text::ParseWords;
use QRZ;
use Buck;
use K4UTE;

use vars qw($version);

$version = "1.1";

sub cease
{
	$SIG{INT} = $SIG{TERM} = 'IGNORE';
	exit(0);
}

sub trancode
{
	$_ = shift;

	return 'Continue' if /100/;
	return 'Switching protocols' if /101/;
	
	return 'Ok' if /200/;
	return 'Created' if /201/;
	return 'Accepted' if /202/;
	return 'Non Authoritive' if /203/;
	return 'No Content' if /204/;
	return 'Reset Content' if /205/;
	return 'Partial Content' if /206/;

	return 'Multiple Choices' if /300/;
	return 'Moved Permanently' if /301/;
	return 'Found, redirect' if /302/;
	return 'See Other' if /303/;
	return 'Not modified' if /304/;
	return 'Use proxy' if /305/;

	return 'Bad request' if /400/;
	return 'Unauthorized' if /401/;
	return 'Payment required' if /402/;
	return 'Forbidden' if /403/;
	return 'Not Found' if /404/;
	return 'Method not allowed' if /405/;
	return 'Not acceptable' if /406/;
	return 'Proxy authentication required' if /407/;
	return 'Request timeout' if /408/;
	return 'Conflict' if /409/;
	return 'Gone' if /410/;
	return 'Length required' if /411/;
	return 'Precondition failed' if /412/;
	return 'Request entity too large' if /413/;
	return 'Request-URI too long' if /414/;
	return 'Unsupported media type' if /415/;
	return 'Requested range not satifiable' if /416/;
	return 'Expectation failed' if /417/;
	
    return 'Internal server error' if /500/;
	return 'Not implemented' if /501/;
	return 'Bad gateway' if /502/;
	return 'Service unavailable' if /503/;
	return 'Gateway timeout' if /504/;
	return 'HTTP version not supported' if /505/;
	
	return 'Unknown';
}

sub genpat
{
	my $s = shift;
	$s =~ s/\*/\\S+/g;
	$s =~ s/\b(?:THE|\&|A|AND|OR|NOT)\b//gi;
	$s =~ s/(?:\(|\))//g;
	return join('|', split(/\s+/, $s));
}

# qrz specific routines
sub req_qrz
{
	my ($ua, $call, $title) = @_;
	my $sreq = "http://www.qrz.com/callsign.html?callsign=$call"; 
#	print "$sreq\n";
	my $req = HTTP::Request->new('GET', $sreq);
    return $ua->register($req);
}

sub parse_qrz
{
	my ($fh, $call, $title, $code, $content) = @_;
	if ($code != 200) {
		print $fh "QRZ|$code|", trancode($code), "\n";
		return;
	}

	# parse the HTML
	my $r = new QRZ $call;
	$r->debug(0);
	my $i;
    my $chunk;
	my $l = length $content;
	for ($i = 0; $i < $l && ($chunk = substr($content, $i, 512)); $i += 512) {
		$r->parse($chunk);
	}
	$r->eof;
	
	my @lines = $r->answer;
	for (@lines) {
		print $fh "QRZ|$code|$_\n" if $_;
	}
	print "lines: ", scalar @lines, "\n";
}

# k4ute specific routines
sub req_ute
{
	my ($ua, $call, $title) = @_;
	my $sreq = "http://no4j.com/nfdxa/qsl/index.asp?dx=$call"; 
#	print "$sreq\n";
	my $req = HTTP::Request->new('GET', $sreq);
    return $ua->register($req);
}

sub parse_ute
{
	my ($fh, $call, $title, $code, $content) = @_;
	if ($code != 200) {
		print $fh "UTE|$code|", trancode($code), "\n";
		return;
	}

	# parse the HTML
	my $r = new K4UTE $call;
	$r->debug(0);
	my $i;
    my $chunk;
	my $l = length $content;
	for ($i = 0; $i < $l && ($chunk = substr($content, $i, 512)); $i += 512) {
		$r->parse($chunk);
	}
	$r->eof;
	
	my @lines = $r->answer;
	for (@lines) {
		print $fh "UTE|$code|$_\n" if $_;
	}
	print "lines: ", scalar @lines, "\n";
}

# buckmaster specific routines
sub req_buck
{
	my ($ua, $call, $title) = @_;
	my $sreq = "http://www.buck.com/cgi-bin/do_hamcallexe"; 
#	print "$sreq\n";
	my $req = HTTP::Request->new('POST', $sreq);
	$req->add_content("entry=$call");
    return $ua->register($req);
}

sub parse_buck
{
	my ($fh, $call, $title, $code, $content) = @_;
	if ($code != 200) {
		print $fh "BCK|$code|", trancode($code), "\n";
		return;
	}

	# parse the HTML
	my $r = new Buck $call;
	$r->debug(0);
	my $i;
    my $chunk;
	my $l = length $content;
	for ($i = 0; $i < $l && ($chunk = substr($content, $i, 512)); $i += 512) {
		$r->parse($chunk);
	}
	$r->eof;
	
	my @lines = $r->answer;
	for (@lines) {
		print $fh "BCK|$code|$_\n" if $_;
	}
	print "lines: ", scalar @lines, "\n";
}


# this is what is called when an incoming request is taken
sub child
{
	my $fh = shift;
	
	my $line;

	if (defined ($line = <$fh>)) {
		$line =~ s/[\r\n]+$//g;
		print "{$line}\n";
	} else {
		return;
	}

	$line =~ s/^[^[A-Za-z0-9\|]]+//g;
	
	my ($call, $title) = split /\|/, $line;
	return if $call eq 'quit' || $call eq 'QUIT';

	print "{A = '$call'";
	print $title ?  ", T = '$title'}\n" : "}\n";

	my $ua = LWP::Parallel::UserAgent->new;

	# set up various UA things
	$ua->duplicates(0);      # ignore duplicates
	$ua->timeout(30);        
	$ua->redirect(1);        # follow 302 redirects 
	$ua->agent("DXSpider callbot $version");

	my $res;
	my $art = uri_escape($call);
	my $tit = uri_escape($title);

	# qrz
	if ($res = req_qrz($ua, $art, $tit)) {
		print $fh "QRZ|500\n";
	}
	# buckmaster
	if ($res = req_buck($ua, $art, $tit)) {
		print $fh "BCK|500\n";
	}
	# ute
	if ($res = req_ute($ua, $art, $tit)) {
		print $fh "UTE|500\n";
	}

	# wait for all the results to come back
	my $entries = $ua->wait();
	
	for (keys %$entries) {
		$res = $entries->{$_}->response;
		my $uri = $res->request->url;
		my $code = $res->code;
		print "url: ", $uri, " code: ", $code, "\n";

		# now parse each result
		for ($uri) {
			parse_qrz($fh, $call, $title, $code, $res->content), last if /www.qrz.com/i;
			parse_buck($fh, $call, $title, $code, $res->content), last if /www.buck.com/i;
			parse_ute($fh, $call, $title, $code, $res->content), last if /no4j.com/i;
		}
	}
	cease(0);
}

$SIG{INT} = \&cease;
$SIG{QUIT} = \&cease;
$SIG{HUP} = 'IGNORE';
STDOUT->autoflush(1);

my $server = new ForkingServer \&child;

$server->allow('.*');
$server->run;

cease(0);





