#
# Display QSL information from the local database
#
# Copyright (c) 2003 Dirk Koopman G1TLH
#
#
#

my ($self, $line) = @_;
my @call = split /\s+/, uc $line;
my @out;

#$DB::single=1;

return (1, $self->msg('db3', 'QSL')) unless $QSL::dbm;

foreach my $call (@call) {
	my $q = QSL::get($call);
	if ($q) {
		my $c = $call;
		push @out, $self->msg('qsl1') unless @out;
		for (sort {$b->[2] <=> $a->[2]} @{$q->[1]}) {
			push @out, sprintf "%-14s %-10s %4d  %s   %s", $c, $_->[0], $_->[1], cldatetime($_->[2]), $_->[3];
			$c = "";
		}
	} else {
		push @out, $self->msg('db2', $call, 'DxQSL DB');
	}
}

return (1, @out);
