#
# Log the current values of the DXDebug dbgring butter
#
#
#
my $self = shift;
my $line = shift;;
return (1, $self->msg('e5')) unless $self->priv >= 9;

DXDebug::dbgprintring();
DXDebug::dbgclearring() if $line =~ /^clear$/;

return (1, 'Contents of debug ring buffer logged. View with watchdbg.');
