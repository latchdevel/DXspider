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
		$user->wantrbn(1);
		$user->put;
		push @out, $self->msg('wante', 'RBN', $call);
	} else {
		push @out, $self->msg('e3', "Set wantrbn", $call);
	}
}
return (1, @out);
