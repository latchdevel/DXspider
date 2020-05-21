#
# the export the user file to ascii command
#
#
#
my $self = shift;
return (1, $self->msg('e5')) unless $self->priv >= 9;

my $count = DXUser::writeoutjson(); # for now

return (1, "DXUser::writeoutjson - $count lines written");


