#
# The master SQL module
#
#
#
# Copyright (c) 2006 Dirk Koopman G1TLH
#

package DXSql;

use strict;

use DXDebug;

use vars qw($active);
$active = 0;

sub init
{
	my $dsn = shift;
	return unless $dsn;
	return $active if $active;
	
	eval { 
		require DBI;
	};
	unless ($@) {
		import DBI;
		$active++;
	}
	undef $@;
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
		dbg "DXSql $dsn " . $dbh? "connected" : "NOT connected" if isdbg('dxsql');
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

sub do
{
	my $self = shift;
	my $s = shift;
	
	eval { $self->{dbh}->do($s); }; 
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

sub quote
{
	return $_[0]->{dbh}->quote($_[1]);
}

sub prepare
{
	return $_[0]->{dbh}->prepare($_[1]);
}

sub spot_insert_prepare
{
	my $self = shift;
	return $self->prepare('insert into spot values(?' . ',?' x 15 . ')');
}

sub spot_insert
{
	my $self = shift;
	my $spot = shift;
	my $sth = shift;
	
	if ($sth) {
		push @$spot, undef while  @$spot < 15;
		pop @$spot while @$spot > 15;
		eval {$sth->execute(undef, @$spot)};
	} else {
		my $s = "insert into spot values(NULL,";
		$s .= sprintf("%.1f,", $spot->[0]);
		$s .= $self->quote($spot->[1]) . "," ;
		$s .= $spot->[2] . ',';
		$s .= (length $spot->[3] ? $self->quote($spot->[3]) : 'NULL') . ',';
		$s .= $self->quote($spot->[4]) . ',';
		$s .= $spot->[5] . ',';
		$s .= $spot->[6] . ',';
		$s .= (length $spot->[7] ? $self->quote($spot->[7]) : 'NULL') . ',';
		$s .= $spot->[8] . ',';
		$s .= $spot->[9] . ',';
		$s .= $spot->[10] . ',';
		$s .= $spot->[11] . ',';
		$s .= (length $spot->[12] ? $self->quote($spot->[12]) : 'NULL') . ',';
		$s .= (length $spot->[13] ? $self->quote($spot->[13]) : 'NULL') . ',';
		$s .= (length $spot->[14] ? $self->quote($spot->[14]) : 'NULL') . ')';
		eval {$self->do($s)};
	}
}

sub spot_search
{
	my $self = shift;
	my ($expr, $dayfrom, $dayto, $from, $to, $hint, $dofilter, $dxchan) = @_;
	$dayfrom = 0 if !$dayfrom;
	$dayto = $Spot::maxdays unless $dayto;
	$dayto = $dayfrom + $Spot::maxdays if $dayto < $dayfrom;
	my $today = Julian::Day->new(time());
	my $fromdate = $today->sub($dayfrom);
	my $todate = $fromdate->sub($dayto);
	$from = 0 unless $from;
	$to = $Spot::defaultspots unless $to;
	
	dbg("DXSql expr: $expr") if isdbg('search');
	if ($expr =~ /\$r->/) {
		$expr =~ s/(?:==|eq)/ = /g;
		$expr =~ s/\$r->\[10\]/spotteritu/g;
		$expr =~ s/\$r->\[11\]/spottercq/g;
		$expr =~ s/\$r->\[12\]/spotstate/g;
		$expr =~ s/\$r->\[13\]/spotterstate/g;
		$expr =~ s/\$r->\[14\]/ipaddr/g;
		$expr =~ s/\$r->\[0\]/freq/g;
		$expr =~ s/\$r->\[1\]/spotcall/g;
		$expr =~ s/\$r->\[2\]/time/g;
		$expr =~ s/\$r->\[3\]/comment/g;
		$expr =~ s/\$r->\[4\]/spotter/g;
		$expr =~ s/\$r->\[5\]/spotdxcc/g;
		$expr =~ s/\$r->\[6\]/spotterdxcc/g;
		$expr =~ s/\$r->\[7\]/origin/g;
		$expr =~ s/\$r->\[8\]/spotitu/g;
		$expr =~ s/\$r->\[9\]/spotcq/g;
		$expr =~ s/\|\|/ or /g;
		$expr =~ s/\&\&/ and /g;
		$expr =~ s/=~\s*m\{\^([%\w]+)[^\}]*\}/ like '$1\%'/g;
	} else {
		$expr = '';
	}  
	my $fdays = $dayfrom ? "time <= " . ($main::systime - ($dayfrom * 86400)) : "";
	my $days = "time >= " . ($main::systime - ($dayto * 86400));
	my $trange = $fdays ? "($fdays and $days)" : $days;
	$expr .= $expr ? " and $trange" : $trange;
    my $s = qq{select freq,spotcall,time,comment,spotter,spotdxcc,spotterdxcc,
origin,spotitu,spotcq,spotteritu,spottercq,spotstate,spotterstate,ipaddr from spot
where $expr limit $to};
    dbg("DXSql expr: $s") if isdbg('search');
	my $ref = $self->{dbh}->selectall_arrayref($s);
	return @$ref;
}

1;

