#
# the bye command
#
# $Id$
#

my $self = shift;

# log out text
if ($self->is_user && -e "$main::data/logout") {
	open(I, "$main::data/logout") or confess;
	my @in = <I>;
	close(I);
	$self->send_now('D', @in);
	sleep(1);
}

$self->disconnect;

return (1);
