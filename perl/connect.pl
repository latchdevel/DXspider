#!/usr/bin/perl
#
# connect to an external entity
#
# This is the routine that is called by the cluster to manage
# an outgoing connection to the point where it is 'connected'.
# From there the client program is forked and execed over the top of
# this program and that connects back to the cluster as though
# it were an incoming connection.
#
# Essentially this porgram does the same as chat in that there
# are 'expect', 'send' pairs of strings. The 'expect' string is 
# a pattern. You can include timeout and abort string statements
# at any time.
#
# Commands are:-
#
# connect <type> <destination>|<program>
# timeout <secs>
# abort <regexp>
# client <client name> <parameters>
# '<regexp>' '<send string>'
#
# Copyright (c) Dirk Koopman G1TLH
#
# $Id$
#

# search local then perl directories
BEGIN {
  # root of directory tree for this system
  $root = "/spider"; 
  $root = $ENV{'DXSPIDER_ROOT'} if $ENV{'DXSPIDER_ROOT'};

  unshift @INC, "$root/perl";   # this IS the right way round!
  unshift @INC, "$root/local";
}

use DXVars;
use IO::Socket;
use Carp;

$timeout = 30;         # default timeout for each stage of the connect
$abort = '';           # default connection abort string
$path = "$root/connect";    # the basic connect directory
$client = "$root/perl/client.pl";   # default client

$connected = 0;        # we have successfully connected or started an interface program

exit(1) if !$ARGV[0];       # bang out if no callsign
open(IN, "$path/$ARGV[0]") or exit(2);

while (<IN>) {
  chomp;
  next if /^\s*#/o;
  next if /^\s*$/o;
  doconnect($1, $2) if /^\s*co\w*\s+(.*)$/io;
  doclient($1) if /^\s*cl\w*\s+(.*)$/io;
  doabort($1) if /^\s*a\w*\s+(.*)/io;
  dotimeout($1) if /^\s*t\w*\s+(\d+)/io;
  dochat($1, $2) if /\s*\'(.*)\'\s+\'(.*)'/io;
}

sub doconnect
{
  my ($sort, $name) = @_;
  print "connect $sort $name\n";
}

sub doabort
{
  my $string = shift;
  print "abort $string\n";
}

sub dotimeout
{
  my $val = shift;
  print "timeout $val\n";
}

sub dochat
{
  my ($expect, $send) = @_;
  print "chat '$expect' '$send'\n";
}

sub doclient
{
  my $cl = shift;
  print "client $cl\n";
}
