#
# the export the user file to ascii command
#
#
#
my $self = shift;
my $line = shift;;
return (1, $self->msg('e5')) unless $self->priv >= 9;

my ($fn, $flag) = split /\s+/, $line;
$fn ||= 'user_json';
unless ($fn && $fn eq 'user_json') {
	$fn =~ s|[/\.]||g;
	$fn = "/tmp/$fn";
}
my $strip = $flag eq 'strip';

my @out = DXUser::export_json($fn, $strip);

return (1, @out);


