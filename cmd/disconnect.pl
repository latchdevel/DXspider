#
# disconnect a local user
#
my ($self, $line) = @_;
my @calls = split /\s+/, $line;
my $call;
my @out;

if ($self->priv < 5) {
	return (1, $self->msg('e5'));
}

foreach $call (@calls) {
	$call = uc $call;
	next if $call eq $main::mycall;
	my $dxchan = DXChannel->get($call);
	if ($dxchan) {
		if ($dxchan->is_node) {
#			$dxchan->send_now("D", DXProt::pc39($main::mycall, $self->msg('disc1', $self->call)));
		} else {
			return (1, $self->msg('e5')) if $self->priv < 8;
			$dxchan->send_now('D', $self->msg('disc1', $self->call));
		} 
		$dxchan->disconnect;
		push @out, $self->msg('disc2', $call);
	} elsif (my $out = grep {$_->{call} eq $call} @main::outstanding_connects) {
		unless ($^O =~ /^MS/i) {
			kill 'TERM', $out->{pid};
		}
		@main::outstanding_connects = grep {$_->{call} ne $call} @main::outstanding_connects;
		push @out, $self->msg('disc2', $call);
	} else {
		push @out, $self->msg('e10', $call);
	}
}

return (1, @out);
