#
# unlock a locked out user 
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
	unless ($self->remotecmd) {
		if ($ref = DXUser->get_current($call)) {
			$ref->lockout(0);
			$ref->put();
			push @out, $self->msg("lockoutun", $call);
		} else {
			push @out, $self->msg('e3', 'unset/lockout', $call);
		}
	} else {
		push @out, $self->msg('sorry');
	}
}
return (1, @out);
