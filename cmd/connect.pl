#
# connect a cluster station
#
my $self = shift;
my $call = uc shift;
my $lccall = lc $call;

return (1, $self->msg('e5')) if $self->priv < 5;
return (1, $self->msg('e6')) unless $call gt ' ';
return (1, $self->msg('already', $call)) if DXChannel::get($call);
return (1, $self->msg('outconn', $call)) if grep {$_->{call} eq $call} @main::outstanding_connects;
return (1, $self->msg('conscript', $lccall)) unless -e "$main::root/connect/$lccall";

my $user = DXUser->get($call);
return (1, $self->msg('lockout', $call)) if $user && $user->lockout;

my @out;
push @out, $self->msg('constart', $call);
my $fn = "$main::root/connect/$lccall";

my $f = new IO::File $fn;
if ($f) {
	my @f = <$f>;
	$f->close;
	ExtMsg::start_connect($call, @f);
} else {
	push @out, $self->msg('e3', 'connect', $fn);
}
return (1, @out);




