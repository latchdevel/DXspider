#
# connect a cluster station
#
my $self = shift;
my $call = uc shift;
my $lccall = lc $call;

return (0) if $self->priv < 8;
return (1, $self->msg('e6')) unless $call gt ' ';
return (1, $self->msg('already', $call)) if DXChannel->get($call);
return (1, $self->msg('conscript', $lccall)) unless -e "$main::root/connect/$lccall";

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



