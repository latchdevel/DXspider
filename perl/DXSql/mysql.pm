#
# Module for SQLite DXSql variants
#
# Stuff like table creates and (later) alters
#
# $Id$
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
	push @out, $sth->fetchrow_array;
	$sth->finish;
	return @out;
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
spotterstate char(2)
)};
	$self->do($s);
}

sub spot_add_indexes
{
	my $self = shift;
	$self->do('create index spot_ix1 on spot(time desc)');
	dbg('adding spot index ix1');
	$self->do('create index spot_ix2 on spot(spotcall asc)');
	dbg('adding spot index ix2');
}


1;  
