#
# (optional) ARRL Dx Database handling
#
# $Id$
#
# Copyright (c) 2005 Dirk Koopman G1TLH
#

use strict;

package ARRL::DX;

use vars qw($VERSION $BRANCH $dbh $dbname %tabledefs $error %stop $limit);

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

%stop = (
		 A => 1,
		 ACTIVITY => 1,
		 AND => 1,
		 ARE => 1,
		 AS => 1,
		 AT => 1,
		 BE => 1,
		 BUT => 1,
		 FOR => 1,
		 FROM => 1,
		 HAS => 1,
		 HAVE => 1,
		 HE => 1,
		 I => 1,
		 IF => 1,
		 IN => 1,
		 IS => 1,
		 IT => 1,
		 LOOK => 1,
		 LOOKS => 1,
		 NOT => 1,
		 OF => 1,
		 ON => 1,
		 OR => 1,
		 OUT => 1,
		 SHE => 1,
		 SO => 1,
		 THAT => 1,
		 THE => 1,
		 THEM => 1,
		 THEY => 1,
		 THIS => 1,
		 THIS => 1,
		 TO => 1,
		 WAS => 1,
		 WHERE => 1,
		 WILL => 1,
		 WITH => 1,
		 YOU => 1,

		 JANUARY => 1,
		 FEBRUARY => 1,
		 MARCH => 1,
		 APRIL => 1,
		 MAY => 1,
		 JUNE => 1,
		 JULY => 1,
		 AUGUST => 1,
		 SEPTEMBER => 1,
		 OCTOBER => 1,
		 NOVEMBER => 1,
		 DECEMBER => 1,
		);

$limit = 10;

sub do_connect
{
	unless ($dbh) {
		$dbh = DBI->connect("dbi:SQLite:dbname=$dbname", "", "");
		unless ($dbh) {
			dbg($DBI::errstr);
			Log('err', $DBI::errstr);
			$error = $DBI::errstr;
			return;
		}
	}
	return $dbh;
}

sub drop
{
	return unless do_connect();
	my $sth = $dbh->prepare("select name,type from sqlite_master where type = 'table'") or $error = $DBI::errstr, return;
	$sth->execute or $error = $DBI::errstr, return;
	while (my @row = $sth->fetchrow_array) {
		$dbh->do("drop table $row[0]");
	}
	$sth->finish;
}

sub create
{
	return unless $dbh;
	
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

sub new
{
	my $pkg = shift;
	my $class = ref $pkg || $pkg;
	my %args = @_;
	
	$error = undef;
	
	unless ($dbh) {
		return unless do_connect();
		create();
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
				$self->{year} = $3;
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
	$sth->execute($self->{para}, $self->{date}, "$self->{year}-$self->{id}");
	my $lastrow = $dbh->func('last_insert_rowid');
	$sth->finish;
	

#	my @w = split /[.,;:\s"'\$\%!£^&\*\(\)\[\]\{\}\#\<\>+=]+/, $self->{para};
	my @w = split m|[\b\s]+|, $self->{para};
#	print join(' ', @w), "\n";
	$sth = $dbh->prepare("insert into refer values(?,?,?,?)");
	
	my $i = 0;
	for (@w) {
		
		# starts with a capital letter that isn't Q
		if (/^[A-PR-Z]/ || m|\d+[A-Z][-/A-Z0-9]*$|) {
			# not all digits
			next if /^\d+$/;
			
			# isn't a stop word
			my $w = uc;
			$w =~ s/\W+$//;
			unless ($stop{$w}) {
				# add it into the word list
				$sth->execute($w, $lastrow, $self->{date}, $i);
#				print " $w";
			}
		}
		$i++;
	}
	$sth->finish;
}

sub query
{
	my $self = shift;
	my %args = @_;
	my @out;
	
	if ($args{'q'}) {
        my @w = map { s|[^-/\w]||g; uc $_ } split /\s+/, $args{'q'};
		if (@w) {
			my $s = qq{select distinct p, t, bullid from (select distinct rowid from refer where };
			while (@w) {
				my $w = shift @w;
				$s .= qq{r like '$w\%'};
				$s .= ' or ' if @w;
			}
			my $l = $args{l}; 
			$l =~ s/[^\d]//g;
			$l ||= $limit;
			$s .= qq{ order by t desc limit $l), paragraph where paragraph.ROWID=rowid};
			my $sth = $dbh->prepare($s) or $error = $DBI::errstr, return @out;
			$sth->execute;
			while (my @row = $sth->fetchrow_array) {
				push @out, \@row;
			}
			$sth->finish;
		}
	}
	return @out;
}

sub close
{
	$dbh->disconnect;
	undef $dbh;
}
1;
