#
# show msgs system status
#
# Copyright (c) 2000 Dirk Koopman G1TLH
#
# $Id$
#
my ($self, $line) = @_;
return (0, $self->msg('e5')) if $self->priv < 5;

my @out;

if (!$line || $line =~ /^b/i) {
	push @out, "Busy Queue";
	push @out, "----------";
	for (keys %DXMsg::busy) {
		my $r = $DXMsg::busy{$_};
		push @out, "$_ : $r->{msgno}, $r->{from} -> $r->{to}, $r->{subject}\n";
	}
}
if (!$line || $line =~ /^w/i) {
	push @out, "Work Queue";
	push @out, "----------";
	for (keys %DXMsg::work) {
		my $r = $DXMsg::work{$_};
		push @out, print_all_fields($self, $r, "Msg Parameters $msgno");
	}
}

return (0, @out);
