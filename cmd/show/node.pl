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
	use DB_File;
	
	my ($action, $count, $key, $data);
	for ($action = R_FIRST, $count = 0; !$DXUser::dbm->seq($key, $data, $action); $action = R_NEXT) {
		if ($data =~ m{sort => '[ACRSX]'}) {
		    push @call, $key;
		}
		++$count;
	} 
}

my $call;
foreach $call (@call) {
	my $clref = DXCluster->get_exact($call);
	my $uref = DXUser->get_current($call);
	my ($sort, $ver);
	
	my $pcall = sprintf "%-11s", $call;
	push @out, $self->msg('snode1') unless @out > 0;
	if ($uref) {
		$sort = "Unknwn";
		$sort = "Spider" if $uref->is_spider;
		$sort = "AK1A  " if $uref->is_ak1a;
		$sort = "Clx   " if $uref->is_clx;
		$sort = "User  " if $uref->is_user;
		$sort = "BBS   " if $uref->is_bbs;
		$sort = "DXNet " if $uref->is_dxnet;
		$sort = "ARClus" if $uref->is_arcluster;
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
	if ($uref->is_spider) {
		push @out, $self->msg('snode2', $pcall, $sort, "$ver  ");
	} else {
		push @out, $self->msg('snode2', $pcall, $sort, $ver ? "$major\-$minor.$subs" : "      ");
	}
}

return (1, @out, $self->msg('rec', $count));




