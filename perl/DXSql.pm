#
# The master SQL module
#
# $Id$
#
# Copyright (c) 2006 Dirk Koopman G1TLH
#

package DXSql;

use strict;

use vars qw($VERSION $BRANCH);
$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /\d+\.\d+\.(\d+)\.(\d+)/  || (0,0));
$main::build += $VERSION;
$main::branch += $BRANCH;

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
	my $self;
	
	return undef unless $active;
	my $dbh;
	my ($style) = $dsn =~ /^dbi:(\w+):/;
	my $newclass = "DXSql::$style";
	eval "require $newclass";
	if ($@) {
		$active = 0;
		return undef;
	}
	return bless {}, $newclass;
}

sub connect
{
	my $self = shift; 
	my $dsn = shift;
	my $user = shift;
	my $passwd = shift;
	
	my $dbh;
	eval {
		no strict 'refs';
		$dbh = DBI->connect($dsn, $user, $passwd); 
	};
	unless ($dbh) {
		$active = 0;
		return undef;
	}
	$self->{dbh} = $dbh;
	return $self;
}

sub finish
{
	my $self = shift;
	$self->{dbh}->disconnect;
} 
1;

