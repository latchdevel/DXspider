#
# The master SQL module
#
# $Id$
#
# Copyright (c) 2006 Dirk Koopman G1TLH
#

package DXSql;

use strict;

our $active = 0;

sub init
{
	return $active if $active;
	
	eval { 
		require DBI;
	};
	unless ($@) {
		import DBI;
		$active++;
	}
	return $active;
} 

sub new
{
	my $class = shift;
	my $dsn = shift;
	my $user = shift;
	my $passwd = shift;
	my $self;
	
	return undef unless $active;
	my $dbh;
	eval {$dbh = DBI->connect($dsn, $user, $passwd); };
	$self = bless {dbh => $dbh}, $class if $dbh;
	return $self;
}

sub finish
{
	my $self = shift;
	$self->{dbh}->disconnect;
} 
1;

