#
# load the prefix_data  file after changing it
#
my $self = shift;
return (0, $self->msg('e5')) if $self->priv < 9;
my $out = Prefix::load();
return (1, $out ? $out : $self->msg('ok'));

