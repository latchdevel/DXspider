#
# show the cluster routing tables to the user
#
# Copyright (c) 1998 Dirk Koopman G1TLH
#
# $Id$
#

my ($self, $line) = @_;
my @list = map { uc } split /\s+/, $line;           # list of callsigns of nodes
my @out;
my @nodes = (DXNode::get_all());
my $node;
my @l;
my @val;

push @out, "Node         Callsigns";
if ($list[0] =~ /^NOD/) {
	my @ch = DXProt::get_all_ak1a();
	my $dxchan;
	
	foreach $dxchan (@ch) {
		@val = grep { $_->dxchan == $dxchan } @nodes;
		my $call = $dxchan->call;
		$call = "($call)" if $dxchan->here == 0;
		@l = ();
		push @l, $call;
		
		my $i = 0;
		foreach $call (@val) {
			if ($i >= 5) {
				push @out, sprintf "%-12s %-12s %-12s %-12s %-12s %-12s", @l;
				@l = ();
				push @l, "";
				$i = 0;
			}
			my $s = $call->{call};
			$s = sprintf "(%s)", $s if $call->{here} == 0;
			push @l, $s;
			$i++;
		}
		push @out, sprintf "%-12s %-12s %-12s %-12s %-12s %-12s", @l;
	}
} else {
	# build up the screen from the Node table
	foreach $node (@nodes) {
		next if scalar @list && !grep $node->call eq $_, @list;
		my $call = $node->call;
		$call = "($call)" if $node->here == 0;
		@l = ();
		push @l, $call;
		my $nlist = $node->list;
		@val = values %{$nlist};

		my $i = 0;
		foreach $call (@val) {
			if ($i >= 5) {
				push @out, sprintf "%-12s %-12s %-12s %-12s %-12s %-12s", @l;
				@l = ();
				push @l, "";
				$i = 0;
			}
			my $s = $call->{call};
			$s = sprintf "(%s)", $s if $call->{here} == 0;
			push @l, $s;
			$i++;
		}
		push @out, sprintf "%-12s %-12s %-12s %-12s %-12s %-12s", @l;
	}
}



return (1, @out);
