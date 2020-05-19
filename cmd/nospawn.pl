#!/usr/bin/perl
#
# Useful for debugging. Make sure that the command runs in foreground
#
# Copyright (c) 1999 Dirk Koopman G1TLH
#
my ($self, $line) = @_;

my $mycall = $self->call;


if ($self->priv < 2) {
	Log('DXCommand', "$mycall is trying to nospawn $line locally");
	return (1, $self->msg('e5'));
}
if ($self->remotecmd || $self->inscript) {
	Log('DXCommand', "$mycall is trying to nospawn remotely");
	return (1, $self->msg('e5'));
}

Log('DXCommand', "nospawn '$line' by $mycall");
$self->{_nospawn} = 1;
my @out = $self->run_cmd($line);
delete $self->{_nospawn};

return (1, @out);
