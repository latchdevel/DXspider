#
# unset the RBN seeme flag
#
# Copyright (c) 2000 - Dirk Koopman
#
#
#

my ($self, $line) = @_;
my @out;

return (0, $self->msg('e5')) unless $self->isa('DXCommandmode');

$self->rbnseeme(0);
$self->user->rbnseeme(0);
$self->user->put;
RBN::del_seeme($self->call);

push @out, $self->msg('ok');
return (1, @out);
