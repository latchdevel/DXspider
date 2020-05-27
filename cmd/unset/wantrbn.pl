#
# set the want rbn (at all)
#
# Copyright (c) 2020 - Dirk Koopman
#
#
#

my ($self, $line) = @_;
my @args = split /\s+/, $line;
my $call;
my @out;

@args = $self->call if (!@args || $self->priv < 9);

foreach $call (@args) {
	$call = uc $call;
	my $user = DXUser::get_current($call);
	if ($user) {
		$user->wantrbn(0);
		$user->put;
		push @out, $self->msg('wantd', 'RBN', $call);
	} else {
		push @out, $self->msg('e3', "Unset wantrbn", $call);
	}
}
return (1, @out);
