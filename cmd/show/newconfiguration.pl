#
# show the new style cluster routing tables to the user
#
# Copyright (c) 2001 Dirk Koopman G1TLH
#
# $Id$
#

my ($self, $line) = @_;
my @list = map { uc } split /\s+/, $line;           # list of callsigns of nodes
my @out;
my $nodes_only;

if (@list && $list[0] =~ /^NOD/) {
	$nodes_only++;
	shift @list;
}

# root node
push @out, $main::mycall;

# now show the config in terms of each of the root nodes view
foreach my $n ($main::routeroot->links) {
	my $r = Route::Node::get($n);
	push @out, $r->config($nodes_only, 1, [], @list) if $r;
}
return (1, @out);

