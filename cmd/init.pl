#
# reinit a cluster connection
#
# Copyright (c) 1999 Dirk Koopman G1TLH
#
# $Id$
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
		if ($dxchan->is_node) {
			
			# first clear out any nodes on this dxchannel
			my @gonenodes = grep { $_->dxchan == $dxchan } DXNode::get_all();
			foreach my $node (@gonenodes) {
				next if $node->dxchan == $DXProt::me;
				next unless $node->dxchan == $dxchan;
				DXProt::broadcast_ak1a(DXProt::pc21($node->call, 'Gone, re-init') , $dxchan) unless $dxchan->{isolate}; 
				$node->del();
			}
			$dxchan->send(DXProt::pc38());
			$dxchan->send(DXProt::pc18());
			$dxchan->state('init');
			push @out, $self->msg('init1', $call);
		} 
	} else {
		push @out, $self->msg('e10', $call);
	}
}

return (1, @out);

