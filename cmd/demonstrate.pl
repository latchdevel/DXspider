#!/usr/bin/perl
#
# pretend that you are another user, execute a command
# as that user, then send the output back to them.
#
# This is for educating users....
#
# Copyright (c) 2002 Dirk Koopman G1TLH
#
my ($self, $line) = @_;

my $mycall = $self->call;
my $myuser = $self->user;
my $mypriv = $self->priv;

my ($call, $newline) = split /\s+/, $line, 2;
$call = uc $call;
my $dxchan = DXChannel->get($call);

return (1, $self->msg('e7', $call)) unless $dxchan;
if ($self->remotecmd) {
	Log('DXCommand', "$mycall is trying to 'input' $call remotely");
	return (1, $self->msg('e5'));
}
if ($mypriv < 8) {
	Log('DXCommand', "$mycall is trying to 'input' $call locally");
	return (1, $self->msg('e5'));
}

$call = uc $call;
my $user = $dxchan->user;

# set up basic environment
$self->call($call);
$self->user($user);
$self->priv($dxchan->priv);
Log('DXCommand', "input '$newline' as $call by $mycall");
my @in = $self->run_cmd($newline);
$self->call($mycall);
$self->user($myuser);
$self->priv($mypriv);

$dxchan->send($newline, @in);

return (1, map { "->$call: $_" } @in);
