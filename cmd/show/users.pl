#
# show the users on this cluster from the routing tables
#
# Copyright (c) 1998 Dirk Koopman G1TLH
#
# $Id$
#

my ($self, $line) = @_;
my @list = map { uc } split /\s+/, $line;           # list of callsigns of nodes
my @out;
my $node = (DXNode->get($main::mycall));

push @out, "Callsigns connected to $main::mycall";
my $call;
my $i = 0;
my @l;
my $nlist = $node->list;
my @val = sort {$a->call cmp $b->call} values %{$nlist};
foreach $call (@val) {
  if (@list) {
    next if !grep $call->call eq $_, @list;
  } 
  if ($i >= 5) {
    push @out, sprintf "%-12s %-12s %-12s %-12s %-12s %-12s", @l;
	@l = ();
	$i = 0;
  }
  my $s = $call->{call};
  $s = sprintf "(%s)", $s if $call->{here} == 0;
  push @l, $s;
  $i++;
}
push @out, sprintf "%-12s %-12s %-12s %-12s %-12s %-12s", @l;


return (1, @out);

