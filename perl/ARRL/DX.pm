#
# (optional) ARRL Dx Database handling
#
# $Id$
#
# Copyright (c) 2005 Dirk Koopman G1TLH
#

use strict;

package ARRL::DX;

use vars qw($VERSION $BRANCH $dbh $dbname %tabledefs $error);

#main::mkver($VERSION = q$Revision$);

use DXLog;
use DXDebug;
use DXUtil;
use DBI;
use IO::File;

$dbname = "$main::root/data/arrldx.db";
%tabledefs = (
			  paragraph => 'CREATE TABLE paragraph(p text, t int)',
			  paragraph_t_idx => 'CREATE INDEX paragraph_t_idx ON paragraph(t DESC)',
			  refer => 'CREATE TABLE refer(r text, id int, t int, pos int)',
			  refer_id_idx => 'CREATE INDEX refer_id_idx ON refer(id)',
			  refer_t_idx => 'CREATE INDEX refer_t_idx ON refer(t DESC)',
			 );

sub new
{
	my $pkg = shift;
	my $class = ref $pkg || $pkg;
	my %args = $@;
	
	$error = undef;
	
	unless ($dbh) {
		$dbh = DBI->connect("dbi:SQLite:dbname=$dbname", "", "");
		unless ($dbh) {
			dbg($DBI::errstr);
			Log('err', $DBI::errstr);
			$error = $DBI::errstr;
			return;
		}
		
		# check that all the tables are present and correct
		my $sth = $dbh->prepare("select name,type from sqlite_master") or $error = $DBI::errstr, return;
		$sth->execute or $error = $DBI::errstr, return;
		my %f;
		while (my @row = $sth->fetchrow_array) {
			$f{$row[0]} = $row[1];
		}
		foreach my $t (sort keys %tabledefs) {
			$dbh->do($tabledefs{$t}) unless exists $f{$t};
		}
		$sth->finish;
	}

	my $self = {};
	
	if ($args{file}) {
		if (ref $args{file}) {
			$self->{f} = $args{file};
		} else {
			$self->{f} = IO::File->new($args{file}) or $error = $!, return;
		}
	} 
	
	return bless $self, $class; 
}

sub process
{
	my $self = shift;
	
}

sub insert
{
	my $self = shift;
	
}
1;
