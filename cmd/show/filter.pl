#
# show filter commands
#
# Copyright (c) 2000 Dirk Koopman G1TLH
#
# $Id$
#
my ($self, $line) = @_;
my @f = split /\s+/, $line;
my @out;
my $call = $self->call;

if (@f && $self->priv >= 8) {
	if (is_callsign(uc $f[0])) {
		$call = uc shift @f;
    } elsif ($f[0] eq 'node_default' || $f[0] eq 'user_default') {
		$call = shift @f;
	}
}

my @in;
if (@f) {
	push @in, @f;
} else {
	push @in, qw(ann spots wcy wwv);
}

my $sort;
foreach $sort (@in) {
	my $ref = Filter::read_in($sort, $call, 1);
	push @out, $ref->print($call, $sort, "input") if $ref;
	$ref = Filter::read_in($sort, $call, 0);
	push @out, $ref->print($call, $sort, "") if $ref;
}
push @out, $self->msg('filter3', $call) unless @out;
return (1, @out);
