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

push @out, "Node         Callsigns";
foreach $node (@nodes) {
  if (@list) {
    next if !grep $node->call eq $_, @list;
  }
  my $i = 0;
  my @l;
  my $call = $node->call;
  $call = "($call)" if $node->here == 0;
  push @l, $call;
  my $nlist = $node->list;
  my @val = values %{$nlist};
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


return (1, @out);
