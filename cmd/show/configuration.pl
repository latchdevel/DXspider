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
my @nodes = sort {$a->call cmp $b->call} (DXNode::get_all());
my $node;
my @l;
my @val;

push @out, "Node         Callsigns";
if ($list[0] && $list[0] =~ /^NOD/) {
	my @ch = sort {$a->call cmp $b->call} DXChannel::get_all_nodes();
	my $dxchan;
	
	foreach $dxchan (@ch) {
		@val = sort {$a->call cmp $b->call} grep { $_->dxchan == $dxchan } @nodes;
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
		next if scalar @list && !grep $node->call =~ /^$_/, @list;
		my $call = $node->call;
		$call = "($call)" if $node->here == 0;
		@l = ();
		push @l, $call;
		my $nlist = $node->list;
		@val = sort {$a->call cmp $b->call} values %{$nlist};

		my $i = 0;
		if (@val == 0 && $node->users) {
			push @l, sprintf "(%d users)", $node->users;
		}
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
