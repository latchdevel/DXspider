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
my @nodes = sort {$a->call cmp $b->call} (Route::Node::get_all());
my $node;
my @l;
my @val;

push @out, $self->msg('showconf');
if ($list[0] && $list[0] =~ /^NOD/) {
	my @ch = sort {$a->call cmp $b->call} DXChannel::get_all_nodes();
	my $dxchan;
	
	foreach $dxchan (@ch) {
		@val = sort {$a->call cmp $b->call} grep { $_->dxchan == $dxchan } @nodes;
		@l = ();
		my $call = $dxchan->call;
		$call ||= '???';
		$call = "($call)" unless $dxchan->here;
		push @l, $call;
		
		my $i = 0;
		foreach my $ref (@val) {
			if ($i >= 5) {
				push @out, sprintf "%-12s %-12s %-12s %-12s %-12s %-12s", @l;
				@l = ();
				push @l, "";
				$i = 0;
			}
			my $s = $ref->call;
			$s ||= '???';
			$s = sprintf "(%s)", $s unless $ref->here;
			push @l, $s;
			$i++;
		}
		push @l, "" while ($i++ < 5);
		push @out, sprintf "%-12s %-12s %-12s %-12s %-12s %-12s", @l;
	}
} else {
	my $printall;
	
	$printall = 1 if @list && $list[0] =~ /^ALL/i;
	
	# build up the screen from the Node table
	foreach $node (@nodes) {
		unless ($printall) {
			if (@list) {
				next unless grep $node->call =~ /^$_/, @list;
			} else {
				next unless grep $node->dxcc == $_, @main::my_cc;
			}
		}
		my $call = $node->call;
		@l = ();
		$call ||= '???';
		$call = "($call)" unless $node->here;
		push @l, $call;
		@val = sort $node->users;

		my $i = 0;
		if (@val == 0 && $node->usercount) {
			push @l, sprintf "(%d users)", $node->usercount;
		}
		foreach $call (@val) {
			if ($i >= 5) {
				push @out, sprintf "%-12s %-12s %-12s %-12s %-12s %-12s", @l;
				@l = ();
				push @l, "";
				$i = 0;
			}
			my $uref = Route::User::get($call);
			my $s = $call;
			if ($uref) {
				$s = sprintf "(%s)", $call unless $uref->here;
			} else {
				$s = "$call?";
			}
			push @l, $s;
			$i++;
		}
		push @l, "" while ($i++ < 5);
		push @out, sprintf "%-12s %-12s %-12s %-12s %-12s %-12s", @l;
	}
}



return (1, @out);
