#
# set isolation for this node
#
# Please note that this is only effective if the user is not on-line
#
# Copyright (c) 1998 - Dirk Koopman
#
# $Id$
#

my ($self, $line) = @_;
my @args = split /\s+/, $line;
my $call;
my @out;
my $user;
my $create;

return (0) if $self->priv < 9;

foreach $call (@args) {
  $call = uc $call;
  my $chan = DXChannel->get($call);
  if ($chan) {
	push @out, $self->msg('nodee1', $call);
  } else {
    $user = DXUser->get($call);
	$create = !$user;
	$user = DXUser->new($call) if $create;
	if ($user) {
	  $user->isolate(1);
	  $user->close();
      push @out, $self->msg($create ? 'isoc' : 'iso', $call);
	} else {
      push @out, $self->msg('e3', "Set/Isolate", $call);
	}
  }
}
return (1, @out);
