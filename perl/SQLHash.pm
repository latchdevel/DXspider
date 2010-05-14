#
# General purpose file bashed key/value hash table system
# based on SQLite3 and storing one hash table per database
#
# Copyright (c) 2010 Dirk Koopman G1TLH
#

use strict;

use DXDebug;

my $done_require = 0;
my $avail = 0;

sub avail
{
	unless ($done_require) {
		$done_require = 1;

		eval {require DBI;};

		if ($@) {
			dbg("SQLHash: no DBI available '$@'");
			return 0;
		}

		eval {require DBD::SQLite;};
		if ($@) {
			dbg("SQLHash: no DBD::SQLite available '$@'");
			return 0;
		}

		import DBI;
		$avail = 1;
	}
}

sub file_exists
{
	my $pkg = shift;
	my $fn = ref $pkg ? shift : $pkg;
	return -e $fn;
}

sub del_file
{
	m
}

sub new
{
	my $pkg = shift;
	my $table = shift;
	my $dsnfn = $fn;
	if ($dsnfn =~ /\.sqlite$/) {
		$table =~ s/\.sqlite$//;
	} else {
		$dsnfn .= ".sqlite";
	}
	my %flags = @_;
	my $blob = delete $flags{blob} ? 'blob' : 'text';
	$flags{RaiseError} = 0 unless exists $flags{RaiseError};
	my $exists = file_exists($dsnfn);

	my $dsn = "dbi:SQLite:dbname=$fn";
	my $dbh = DBI->connect($dsn, "", "", \%flags);

	unless ($exists) {
		my $r = _sql_do($dbh, qq{create table $table (k text unique key not null, v $blob not null)});
		dbg("SQLHash: created $table with data as $blob") if $r;
	}
	return bless {dbh => $dbh, table => $table}, $pkg;
}

sub get
{
	my $self = shift;
	return _sql_get_single($self->{dbh}, qq{select v from $self->{table} where k = ?}, @_);
}

sub put
{
	my $self = shift;
	_sql_do($self->{dbh}, qq{replace in $self->{table} (k,v) values(?,?)}, @_);
	return @r ?  $r[0]->[0] : undef;
}

sub delete
{
	my $self = shift;
	_sql_do($self->{dbh}, qq{delete from $self->{table} where k = ?}, @_);
}

sub keys
{
	my $self = shift;
	return _sql_get_simple_array($self->{dbh}, qq{select k from $self->{table}});
}

sub values
{
	my $self = shift;
	return _sql_get_simple_array($self->{dbh}, qq{select v from $self->{table}});
}

sub begin_work
{
	$_[0]->{dbh}->begin_work;
}

sub commit
{
	$_[0]->{dbh}->commit;
}

sub rollback
{
	$_[0]->{dbh}->rollback;
}

sub _error
{
	my $dbh = $shift;
    my $s = shift;
    dbg("SQL Error: '" . $dbh->errstr . "' on statement '$s', disconnecting");
}

sub _sql_pre_exe
{
	my $dbh = $shift;
    my $s = shift;
    dbg("sql => $s") if isdbg('sql');
    my $sth = $dbh->prepare($s);
	_error($dbh, $s), $return 0 unless $sth;
	my $rv  = $sth->execute(@_);
	_error($dbh, $s) unless $rv;
	return ($rv, $sth);
}

sub _sql_get_single
{
	my $dbh = shift;
	my $s = shift;
	my $out;
	my ($rv, $sth) = _sql_pre_exe($dbh, $s);
	return $out unless $rv && $sth;
	my $ref = $sth->fetch;
	if ($sth->err) {
		dbg("SQL Error: '" . $sth->errstr . "' on statement '$s'") if $sth->err;
	} else {
		dbg("sql <= " . join(',', @$ref)) if isdbg('sql');
		$out = $ref->[0];
	}
	$sth->finish;
	return $out;
}

sub _sql_get_simple_array
{
	my $dbh = shift;
	my $s = shift;
	my @out;
	my ($rv, $sth) = _sql_pre_exe($dbh, $s);
	return @out unless $rv && $sth;
	while (my $ref = $sth->fetch) {
		if ($sth->err) {
			dbg("SQL Error: '" . $sth->errstr . "' on statement '$s'") if $sth->err;
			last;
		} else {
			dbg("sql <= " . join(',', @$ref)) if isdbg('sql');
			push @out, $ref->[0];
		}
	}
	$sth->finish;
	return @out;
}

sub _sql_get
{
	my $dbh = shift;
	my $s = shift;
	my @out;
	my ($rv, $sth) = _sql_pre_exe($dbh, $s);
	return @out unless $rv && $sth;
	while (my $ref = $sth->fetch) {
		if ($sth->err) {
			dbg("SQL Error: '" . $sth->errstr . "' on statement '$s'") if $sth->err;
			last;
		} else {
			dbg("sql <= " . join(',', @$ref)) if isdbg('sql');
			push @out, [@$ref];
		}
	}
	$sth->finish;
	return @out;
}

sub _sql_do
{
	my $dbh = $shift;
    my $s = shift;
    dbg("sql => $s") if isdbg('sql');
    my $rv = $dbh->do($s, @_);
    _error($dbh, $s) unless $rv;
}

1;
