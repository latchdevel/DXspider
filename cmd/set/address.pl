#
# set the address field
#
# Copyright (c) 1998 - Dirk Koopman
#
# $Id$
#

my ($self, $line) = @_;
my $call;
my @out;
my $user;

if ($self->priv >= 5) {             # allow a callsign as first arg
  my @args = split /\s+/, $line;
  $call = UC $args[0];
  $user = DXUser->get_current($call);
  shift @args if $user;
  $line = join ' ', @args;
} else {
  $call = $self->call;
  $user = $self->user;
}

$user->addr($line);
push @out, $self->msg('addr', $call, $line);

return (1, @out);
