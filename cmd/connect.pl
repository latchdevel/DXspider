#
# connect a cluster station
#
my $self = shift;
my $call = uc shift;
return (0) if $self->priv < 9;
return (1, $self->msg('already', $call)) if DXChannel::get($call);

my $prog = "$main::root/local/client.pl";
$prog = "$main::root/perl/client.pl" if ! -e $prog;

my $pid = fork();
if (defined $pid) {
	if (!$pid) {
		# in child
		exec $prog, $call, 'connect';
	} else {
		return(1, $self->msg('constart', $call));
	}
}
return (0, $self->msg('confail', $call, $!))



