#
# the shutdown command
# 
# $Id$
#
my $self = shift;
if ($self->priv >= 5) {
  &main::cease();
}
return (0);
