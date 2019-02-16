#
# the export the user file to ascii command
#
#
#
my $self = shift;
my $line = shift;;
return (1, $self->msg('e5')) unless $self->priv >= 9;

my ($fn, $flag) = split /\s+/, $line;
my $strip = $flag eq 'strip';

my @out = $self->spawn_cmd("export_users", \&DXUser::export, args => [$fn, $strip]);

return (1, @out);


