#
# set user type to 'A' for AK1A node
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

return (0) if $self->priv < 5;

foreach $call (@args) {
  $call = uc $call;
  my $chan = DXChannel->get($call);
  if ($chan) {
	push @out, DXM::msg('nodee1', $call);
  } else {
    $user = DXUser->get($call);
	if ($user) {
	  $user->sort('A');
	  $user->close();
      push @out, DXM::msg('node', $call);
	} else {
      push @out, DXM::msg('e3', "Set Node", $call);
	}
  }
}
return (1, @out);
