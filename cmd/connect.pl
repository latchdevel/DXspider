#
# connect a cluster station
#
my $self = shift;
my $call = uc shift;
my $lccall = lc $call;

return (1, $self->msg('e5')) if $self->priv < 5;
return (1, $self->msg('e6')) unless $call gt ' ';
return (1, $self->msg('already', $call)) if DXChannel->get($call);
return (1, $self->msg('outconn', $call)) if grep {$_->{call} eq $call} @main::outstanding_connects;
return (1, $self->msg('conscript', $lccall)) unless -e "$main::root/connect/$lccall";

my $prog = "$main::root/local/client.pl";
$prog = "$main::root/perl/client.pl" if ! -e $prog;

my $pid = fork();
if (defined $pid) {
	if (!$pid) {
		# in child, unset warnings, disable debugging and general clean up from us
		$^W = 0;
		$SIG{HUP} = 'IGNORE';
		eval "{ package DB; sub DB {} }";
		alarm(0);
		DXChannel::closeall();
		Msg::close_server();
		$SIG{CHLD} = $SIG{TERM} = $SIG{INT} = $SIG{__WARN__} = 'DEFAULT';
		exec $prog, $call, 'connect';
	} else {
		sleep(1);    # do a coordination
		push @main::outstanding_connects, {call => $call, pid => $pid};
		return(1, $self->msg('constart', $call));
	}
}
return (0, $self->msg('confail', $call, $!))



