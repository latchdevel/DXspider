#!/usr/bin/perl
#
# This module impliments the verification routines
#
# Copyright (c) 2002 Dirk Koopman G1TLH
#
# $Id$
# 

package Verify;

use DXChannel;
use DXUtil;
use DXDebug;
use Time::HiRes qw(gettimeofday);
use Digest::SHA1 qw(sha1_base64);

use strict;

use vars qw($VERSION $BRANCH);
$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /\d+\.\d+\.(\d+)\.(\d+)/  || (0,0));
$main::build += $VERSION;
$main::branch += $BRANCH;

sub new
{
	my $class = shift;
	my $self = bless {}, ref($class) || $class; 
	$self->{seed} = shift if @_;
	return $self;
}

sub challenge
{
	my $self = shift;
	my @t = gettimeofday();
	my $r = unpack("xxNxx", pack("d", rand));
	@t = map {$_ ^ $r} @t;
	dbg("challenge r: $r seed: $t[0] $t[1]" ) if isdbg('verify');
	$r = unpack("xxNxx", pack("d", rand));
	@t = map {$_ ^ $r} @t;
	dbg("challenge r: $r seed: $t[0] $t[1]" ) if isdbg('verify');
	return $self->{seed} = sha1_base64(@t, gettimeofday, rand, rand, rand, @_);
}

sub response
{
	my $self = shift;
	return sha1_base64($self->{seed}, @_);
}

sub verify
{
	my $self = shift;
	my $answer = shift;
	my $p = sha1_base64($self->{seed}, @_);
	return $p eq $answer;
}

1;
