#
# Module for SQLite DXSql variants
#
# Stuff like table creates and (later) alters
#
#
#
# Copyright (c) 2005 Dirk Koopman G1TLH
#

package DXSql::mysql;

use DXDebug;

use vars qw(@ISA);
@ISA = qw{DXSql};

sub show_tables
{
	my $self = shift;
	my $s = q(show tables);
	my $sth = $self->prepare($s);
	$sth->execute;
	my @out;
	while (my @t = $sth->fetchrow_array) {
		push @out, @t;
	}
	$sth->finish;
	return @out;
}

sub has_ipaddr
{
	my $self = shift;
	my $s = q(describe spot);
	my $sth = $self->prepare($s);
	$sth->execute;
	while (my @t = $sth->fetchrow_array) {
		if ($t[0] eq 'ipaddr') {
			$sth->finish;
			return 1;
		}
	}
	$sth->finish;
	return undef;
}

sub add_ipaddr
{
	my $self = shift;
	my $s = q(alter table spot add column ipaddr varchar(40));
	$self->do($s);
}

sub spot_create_table
{
	my $self = shift;
	my $s = q{create table spot (
rowid integer auto_increment primary key ,
freq real not null,
spotcall varchar(14) not null,
time int not null,
comment varchar(255),
spotter varchar(14) not null,
spotdxcc smallint,
spotterdxcc smallint,
origin varchar(14),
spotitu tinyint,
spotcq tinyint,
spotteritu tinyint,
spottercq tinyint,
spotstate char(2),
spotterstate char(2),
ipaddr varchar(40)
)};
	$self->do($s);
}

sub spot_add_indexes
{
	my $self = shift;
	dbg('adding spot index ix1');
	$self->do('create index spot_ix1 on spot(time desc)');
	dbg('adding spot index ix2');
	$self->do('create index spot_ix2 on spot(spotcall asc)');
}


1;  
