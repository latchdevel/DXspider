#
# show/node [<node> | <node> ] 
# 
# This command either lists all nodes known about 
# or the ones specified on the command line together
# with some information that is relavent to them 
#
# This command isn't and never will be compatible with AK1A
#
# A special millenium treat just for G4PDQ
#
# Copyright (c) 2000 Dirk Koopman G1TLH
#
# $Id$
#

my ($self, $line) = @_;
return (1, $self->msg('e5')) unless $self->priv >= 1;

my @call = map {uc $_} split /\s+/, $line; 
my @out;

# search thru the user for nodes
unless (@call) {
	@call = sort map { my $ref; (($ref = DXUser->get_current($_)) && $ref->sort ne 'U') ? $_ : () } DXUser::get_all_calls;
}

my $call;
foreach $call (@call) {
	my $clref = DXCluster->get_exact($call);
	my $uref = DXUser->get_current($call);
	my ($sort, $ver);
	
	my $pcall = sprintf "%-11s", $call;
	push @out, $self->msg('snode1') unless @out > 0;
	if ($uref) {
		$sort = "Spider" if $uref->sort eq 'S';
		$sort = "AK1A  " if $uref->sort eq 'A';
		$sort = "clx   " if $uref->sort eq 'C';
		$sort = "Fred  " if $uref->sort eq 'U';
		$sort = "BBS   " if $uref->sort eq 'B';
	} else {
		push @out, $self->msg('snode3', $call);
		next;
	}
	if ($call eq $main::mycall) {
		$sort = "Spider";
		$ver = $main::version;
	} else {
		$ver = $clref->pcversion if $clref && $clref->pcversion;
	}
	
	my ($major, $minor, $subs) = unpack("AAA*", $ver) if $ver;
	if ($sort eq 'Spider') {
		push @out, $self->msg('snode2', $pcall, $sort, "$ver  ");
	} else {
		push @out, $self->msg('snode2', $pcall, $sort, $ver ? "$major\-$minor.$subs" : "      ");
	}
}

return (1, @out);
