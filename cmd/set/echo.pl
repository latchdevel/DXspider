#
# set echoing
#
# Copyright (c) 2000 - Dirk Koopman G1TLH
#
#
#
my $self = shift;
$self->conn->echo(1);
$self->user->wantecho(1);
return (1, $self->msg('echoon'));
