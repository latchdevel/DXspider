#!/usr/bin/perl
#
# Database update routine
#
# Copyright (c) 1999 Dirk Koopman G1TLH
#
my ($self, $line) = @_;
my @out;

my $f;

foreach $f (values %DXDb::avail) {
	push @out, "DB Name          Location   Chain" unless @out;
	push @out, sprintf "%-15s  %-10s %s", $f->name, $f->remote ? $f->remote : "Local", $f->chain ? parray($f->chain) : ""; 
}
return (1, @out);
