#
# unset the here flag
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
	my $dxchan = DXChannel->get($call);
	if ($dxchan) {
		$dxchan->here(0);
		push @out, $self->msg('hereu', $call);
		my $ref = Route::User::get($call);
		$ref = Route::Node::get($call) unless $ref;
		if ($ref) {
			$ref->here(0);
			my $s = DXProt::pc24($ref);
			DXProt::eph_dup($s);
			DXProt::broadcast_all_ak1a($s, $DXProt::me) ;
		}
	} else {
		push @out, $self->msg('e3', "Unset Here", $call);
	}
}

return (1, @out);
