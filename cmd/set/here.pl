#
# set the here flag
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
  my $chan = DXChannel->get($call);
  if ($chan) {
    $chan->here(1);
	push @out, DXM::msg('heres', $call);
  } else {
    push @out, DXM::msg('e3', "Set Here", $call);
  }
}
return (1, @out);
