#
# Log the current values of the DXDebug dbgring butter
#
#
#
my $self = shift;
my $line = shift;;
return (1, $self->msg('e5')) unless $self->priv >= 9;

my @args = split /\s+/, $line;
my $n;
my $doclear;

for (@args) {
	$n = 0+$_ if /^\d+$/;
	$doclear++ if /^clear$/;
}
DXDebug::dbgprintring($n);
DXDebug::dbgclearring() if $doclear;

return (1, 'Contents of debug ring buffer logged. View with watchdbg.');
