#
# set the ve7cc output flag
#
# Copyright (c) 2000 - Dirk Koopman
#
#
#

my ($self, $line) = @_;
my @args = split /\s+/, $line;
my $call;
my @out;

return (0, $self->msg('e5')) unless $self->isa('DXCommandmode');

$self->rbnseeme(1);
$self->user->rbnseeme(1);
RBN::add_seeme($self->call);

push @out, $self->msg('ok');
return (1, @out);
