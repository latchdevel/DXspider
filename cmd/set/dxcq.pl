#
# set the dxdxcq flag
#
# Copyright (c) 2000 - Dirk Koopman
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
		$user->wantdxcq(1);
		$user->put;
		push @out, $self->msg('dxcqs', $call);
	} else {
		push @out, $self->msg('e3', "Set DX CQ", $call);
	}
}
return (1, @out);
