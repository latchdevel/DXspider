#
# set a user's password
#
# Copyright (c) 1998 Iain Phillips G0RDI
# 21-Dec-1998
#
# Syntax:	set/pass <password> <callsign>
#

my ($self, $line) = @_;
my @args = split /\s+/, $line;
my $call;
my $pass = shift @args;
my @out;
my $user;
my $ref;

return (1, $self->msg('e5')) if $self->priv < 9;

foreach $call (@args) {
	$call = uc $call;
	if ($ref = DXUser->get_current($call)) {
		$ref->passwd($pass);
		$ref->put();
		push @out, $self->msg("password", $call);
	} else {
		push @out, $self->msg('e3', 'User record for', $call);
	}
}
return (1, @out);
