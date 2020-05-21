# spawn a command
#
# Note: this command will run _nospawn versions of a cmd (as this is a direct lift from
#       the 'spawn_cmd' in DXCron pm
#

sub handle
{
	my ($self, $line) = @_;
	return (1, $self->msg('e5')) if $self->priv < 6;
	my @out = DXCron::spawn_cmd($line, $self) unless $self->{_nospawn};
	return (1, @out);
}
