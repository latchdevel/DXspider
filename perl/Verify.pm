#!/usr/bin/perl
#
# This module impliments the verification routines
#
# Copyright (c) 2002 Dirk Koopman G1TLH
#
# $Id$
# 

use strict;

package Verify;

use DXUtil;
use DXDebug;
use Digest::SHA1 qw(sha1_base64);

use vars qw($VERSION $BRANCH);
$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /\d+\.\d+\.(\d+)\.(\d+)/  || (0,0));
$main::build += $VERSION;
$main::branch += $BRANCH;

sub new
{
	my $class = shift;
	my $self = bless {}, ref($class) || $class; 
	$self->newsalt(@_);
	return $self;
}

sub newsalt
{
	my $self = shift;
	return $self->{salt} = sha1_base64('RbG4tST2dYPWnh6bfAaq7pPSL04', @_);
}

sub challenge
{
	my $self = shift;
	my $p = substr(sha1_base64($self->{salt}, @_), -6, 6);
	return $p;
}

sub verify
{
	my $self = shift;
	my $answer = shift;
	my $p = substr(sha1_base64($self->{salt}, @_), -6, 6);
	return $p eq $answer;
}

sub salt
{
	my $self = shift;
	return @_ ? $self->{salt} = shift : $self->{salt};
}
1;
