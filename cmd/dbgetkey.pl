#!/usr/bin/perl
#
# Database update routine
#
# Copyright (c) 1999 Dirk Koopman G1TLH
#
my ($self, $line) = @_;
my @f = split /\s+/, $line;
my @out;

my $name = shift @f if @f;
my $db = DXDb::getdesc($name);
return (1, $self->msg('db3', $name)) unless $db;

if ($db->remote) {
	for (@f) {
		my $n = DXDb::newstream($self->call);
		DXProt::route(undef, $db->remote, DXProt::pc44($main::mycall, $db->remote, $n, uc $db->name,uc $_, $self->call));
	}
} else {
	for (@f) {
		my $value = $db->getkey($_);
		if ($value) {
			push @out, split /\n/, $value;
		} else {
			push @out, $self->msg('db2', $_, $db->{name});
		}
	}
}

return (1, @out);
