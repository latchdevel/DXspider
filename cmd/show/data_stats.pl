#
# show the users on this cluster from the routing tables
#
# Copyright (c) 1998 Dirk Koopman G1TLH
#
#
#

sub handle
{
	my ($self, $line) = @_;
	my @list = map { uc } split /\s+/, $line; # list of callsigns of nodes
	my @out;
	if ($list[0] eq 'ALL') {
		shift @list;
		@list = keys %DXChannel::channels;
	}
	push @out, "Data Statitics                 IN                                OUT";
	push @out, "Callsign             Lines             Data            Lines             Data";
	push @out, "-----------------------------------------------------------------------------";
	if (@list) {
		foreach my $call (sort @list) {
			next if $call eq $main::mycall;
			my $dxchan = DXChannel::get($call);
			if ($dxchan) {
				my $conn = $dxchan->conn;
				push @out, sprintf("%-9.9s %16s %16s %16s %16s", $call, comma($conn->{linesin}), comma($conn->{datain}), comma($conn->{linesout}), comma($conn->{dataout}));
			}
		}
	}

	push @out, "-----------------------------------------------------------------------------" if @out > 3;
	push @out, sprintf("%-9.9s %16s %16s %16s %16s", "TOTALS", comma($Msg::total_lines_in), comma($Msg::total_in), comma($Msg::total_lines_out), comma($Msg::total_out));

	return (1, @out);
}

sub comma
{
	my $num = shift;
	return scalar reverse(join(",",unpack("(A3)*", reverse int($num))));
}

