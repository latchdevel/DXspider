#
# set the pc90 flag
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
		$user->wantpc90(1);
		$user->put;
		push @out, $self->msg('set', 'PC90', $call);
	} else {
		push @out, $self->msg('e3', "Set PC90", $call);
	}
}
return (1, @out);
