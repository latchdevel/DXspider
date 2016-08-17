#
# the export the user file to ascii command
#
#
#
my $self = shift;
my $line = shift || "user_asc";
return (1, $self->msg('e5')) unless $self->priv >= 9;

my ($fn, $flag) = split /\s+/, $line;
my $strip = $flag eq 'strip';
return (1, DXUser::export($fn, $strip));
