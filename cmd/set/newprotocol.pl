#
# set the new protocol flag
#
# Copyright (c) 1998 - Dirk Koopman
#
# $Id$
#

my ($self, $line) = @_;
my @args = split /\s+/, $line;
my $call;
my @out;

@args = $self->call if (!@args || $self->priv < 9);

foreach $call (@args) {
	$call = uc $call;
	my $user = DXUser->get_current($call);
	if ($user) {
		$user->wantnp(1);
		$user->put;
		push @out, $self->msg('set', 'New Protocol', $call);
	} else {
		push @out, $self->msg('e3', "Set New Protocol", $call);
	}
}
return (1, @out);
