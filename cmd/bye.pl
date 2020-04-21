#
# the bye command
#
#
#


my $self = shift;
return (1, $self->msg('e5')) if $self->inscript || $self->remotecmd;

my $fn = localdata("logout");
dbg("fn: $fn " . (-e $fn ? 'exists' : 'missing'));

if ($self->is_user && -e $fn) {
	$self->send_file($fn);
	Mojo::IOLoop->timer($Msg::disc_waittime, sub{$self->disconnect});
} else {
	$self->disconnect;
}

return (1);
