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

push @out, $main::routeroot->config($nodes_only, 0, {}, @list);
return (1, @out);

