#!/usr/bin/perl
#
# Database update routine
#
# Copyright (c) 1999 Dirk Koopman G1TLH
#
my ($self, $line) = @_;
my ($name, $remote) = split /\s+/, $line;
my @out;

return (1, $self->msg('e5')) if $self->priv < 9;

return (1, $self->msg('db6', $name)) if DXDb::getdesc($name);
DXDb::new($name, $remote);
push @out, $self->msg($remote ? 'db7' : 'db8', $name, $remote);
return (1, @out);
