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

main::mkver($VERSION = q$Revision$) if main->can('mkver');

use DXLog;
use DXDebug;
use DXUtil;
use DBI;
use IO::File;
use Date::Parse;

$dbname = "$main::root/data/arrldx.db";
%tabledefs = (
			  paragraph => 'CREATE TABLE paragraph(p text, t int, bullid text)',
			  paragraph_t_idx => 'CREATE INDEX paragraph_t_idx ON paragraph(t DESC)',
			  refer => 'CREATE TABLE refer(r text, rowid int, t int, pos int)',
			  refer_id_idx => 'CREATE INDEX refer_id_idx ON refer(rowid)',
			  refer_t_idx => 'CREATE INDEX refer_t_idx ON refer(t DESC)',
			 );

sub new
{
	my $pkg = shift;
	my $class = ref $pkg || $pkg;
	my %args = @_;
	
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

	return unless $self->{f};
	
	my $state;
	my $count;
	
	$dbh->begin_work;
	my $f = $self->{f};
	while (<$f>) {
#		print;
		unless ($state) {
			$state = 'ZC' if /^ZCZC/; 
		} elsif ($state eq 'ZC') {
			if (/\b(ARLD\d+)\b/) {
				$self->{id} = $1;
				$state = 'id';
			}
		} elsif ($state eq 'id') {
			if (/^Newington\s+CT\s+(\w+)\s+(\d+),\s+(\d+)/i) {
				$state = 'date' ;
				$self->{date} = str2time("$1 $2 $3") if $state eq 'date';
			}
		} elsif ($state eq 'date') {
			if (/^$self->{id}/) {
				last unless /DX\s+[Nn]ews\s*$/;
				$state = 'week'; 
			}
		} elsif ($state eq 'week') {
			$state = 'weekro' if /^This\s+week/;
		} elsif ($state eq 'weekro') {
			if (/^\s*$/) {
				$state = 'para';
				$self->{para} = "";
			}
		} elsif ($state eq 'para') {
			if (/^\s*$/) {
				if ($self->{para}) {
					$self->{para} =~ s/^\s+//;
					$self->{para} =~ s/\s+$//;
					$self->{para} =~ s/\s+/ /g;
					$self->insert;
					$self->{para} = "";
					$count++;
				}
			} elsif (/^THIS\s+WEEKEND/) {
				last;
			}
			chomp;
			s/^\s+//;
			s/\s+$//;
			$self->{para} .= $_ . ' ';
		}
	}
	$dbh->commit;
	$self->{f}->close;
	delete $self->{f};
	return $count;
}

sub insert
{
	my $self = shift;
	my $sth = $dbh->prepare("insert into paragraph values(?,?,?)");
	$sth->execute($self->{para}, $self->{date}, $self->{id});
	my $lastrow = $dbh->func('last_insert_rowid');
}

sub close
{
	$dbh->disconnect;
	undef $dbh;
}
1;
