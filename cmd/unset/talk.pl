#
# unset the talk flag
#
# Copyright (c) 1998 - Dirk Koopman
#
# $Id$
#

my ($self, $line) = @_;
my @args = split /\s+/, $line;
my $call;
my @out;

@args = $self->call if (!@args || $self->priv < 9);

foreach $call (@args) {
  $call = uc $call;
  my $user = ($call eq $self->call) ? $self->user :  DXUser->get($call);
  if ($user) {
    $user->talk(0);
	push @out, $self->msg('talku', $call);
  } else {
    push @out, $self->msg('e3', "Unset Talk", $call);
  }
}
return (1, @out);
