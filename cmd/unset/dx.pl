#
# unset the dx flag
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
  my $user = ($call eq $self->call) ? $self->user : DXUser->get($call);
  if ($user) {
    $user->dx(0);
	push @out, DXM::msg('dxu', $call);
  } else {
    push @out, DXM::msg('e3', "Unset DX Spots", $call);
  }
}
return (1, @out);
