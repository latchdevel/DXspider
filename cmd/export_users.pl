#
# the export the user file to ascii command
#
#
#
my $self = shift;
my $line = shift;;
return (1, $self->msg('e5')) unless $self->priv >= 9;

$line ||= 'user_json';
my ($fn) = split /\s+/, $line;
unless ($fn && $fn eq 'user_json') {
	$fn =~ s|[/\.]||g;
	$fn = "/tmp/$fn";
}

my @out = DXUser::export($fn);

return (1, @out);


