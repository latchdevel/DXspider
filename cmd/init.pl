#
# reinit a cluster connection
#
my ($self, $line) = @_;
my @calls = split /\s+/, $line;
my $call;
my @out;

return (1, $self->msg('e5')) if $self->priv < 5;

foreach $call (@calls) {
	$call = uc $call;
	next if $call eq $main::mycall;
	my $dxchan = DXChannel->get($call);
	if ($dxchan) {
		if ($dxchan->is_ak1a) {
			
			# first clear out any nodes on this dxchannel
			my @gonenodes = map { $_->dxchan == $dxchan ? $_ : () } DXNode::get_all();
			foreach my $node (@gonenodes) {
				next if $dxchan == $DXProt::me;
				DXProt::broadcast_ak1a(DXProt::pc21($node->call, 'Gone, re-init') , $dxchan) unless $dxchan->{isolate}; 
				$node->del();
			}
			$dxchan->send(DXProt::pc38());
			$dxchan->send(DXProt::pc18());
			push @out, $self->msg('init1', $call);
		} 
	} else {
		push @out, $self->msg('e10', $call);
	}
}

return (1, @out);

