#
# lock a user out
#
# Copyright (c) 1998 Iain Phillips G0RDI
#
# $Id$
#
my ($self, $line) = @_;
my @args = split /\s+/, $line;
my $call;
# my $priv = shift @args;
my @out;
my $user;
my $ref;

return (1, $self->msg('e5')) if $self->priv < 9;

foreach $call (@args) {
	$call = uc $call;
	if ($ref = DXUser->get_current($call)) {
		$ref->lockout(1);
		$ref->put();
		push @out, $self->msg("lockout", $call);
	} else {
		$ref = DXUser->new($call);
		$ref->lockout(1);
		$ref->put();
		push @out, $self->msg("lockoutc", $call);
	}
}
return (1, @out);
