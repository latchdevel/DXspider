#
# the export the user file to ascii command
#
#
#
my $self = shift;
return (1, $self->msg('e5')) unless $self->priv >= 9;
my $line = shift || "$main::data/user_asc";
return (1, DXUser::export($line));
