#
# unset the pc90 flag
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
		$user->wantpc90(0);
		push @out, $self->msg('pc90u', $call);
	} else {
		push @out, $self->msg('e3', "Unset PC90", $call);
	}
}
return (1, @out);
