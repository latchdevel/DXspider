#
# show the users on this cluster from the routing tables
#
# Copyright (c) 1998 Dirk Koopman G1TLH
#
# $Id$
#

my ($self, $line) = @_;
my @list = map { uc } split /\s+/, $line; # list of callsigns of nodes
my @out;
my $node = $main::routeroot;

push @out, "Callsigns connected to $main::mycall";
my $call;
my $i = 0;
my @l;
my @val = sort $node->users;
foreach $call (@val) {
	if (@list) {
		next if !grep $call eq $_, @list;
	} 
	if ($i >= 5) {
		push @out, sprintf "%-12s %-12s %-12s %-12s %-12s %-12s", @l;
		@l = ();
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
push @out, sprintf "%-12s %-12s %-12s %-12s %-12s %-12s", @l;


return (1, @out);

