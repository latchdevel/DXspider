#
# show any variable
#
# Rape me!
#
# Copyright (c) 1999 - Dirk Koopman G1TLH
#
# $Id$
#

my ($self, $line) = @_;
return (1, $self->msg('e5')) if $self->priv < 9 || $self->remotecmd;
my @f = split /\s+/, $line;
my $f;
my @out;

foreach $f (@f) {
    print "\$f = $f\n";
	my $var = eval "$f";
	if ($var) {
        my $s = Data::Dumper->Dump([ $var ], [ "$f" ]);
		push @out, $s;
		Log('DXCommand', $self->call . " show/var $s");
	} else {
		push @out, $@ ? $@ : $self->msg('e3', 'show/var', $f);
		Log('DXCommand', $self->call . " show/var $f not found" );
	}
}

return (1, @out);
