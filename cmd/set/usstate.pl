#
# set the usstate flag
#
# Copyright (c) 2000 - Dirk Koopman
#
# $Id$
#

my ($self, $line) = @_;
my @args = split /\s+/, $line;
my $call;
my @out;

return (1, $self->msg('db3', 'FCC USDB')) unless $USDB::present;

@args = $self->call if (!@args || $self->priv < 9);

foreach $call (@args) {
	$call = uc $call;
	my $user = DXUser->get_current($call);
	if ($user) {
		$user->wantusstate(1);
		$user->put;
		push @out, $self->msg('usstates', $call);
	} else {
		push @out, $self->msg('e3', "Set US State", $call);
	}
}
return (1, @out);
