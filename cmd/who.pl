#
# who : is online
# a complete list of stations connected
#
# Copyright (c) 1999 Dirk Koopman G1TLH
#
# $Id$


my $self = shift;
my $dxchan;
my @out;

push @out, "  Callsign Type      Started           Name                Ave RTT";

foreach $dxchan ( sort {$a->call cmp $b->call} DXChannel::get_all ) {
    my $call = $dxchan->call();
	my $t = cldatetime($dxchan->startt);
	my $type = $dxchan->is_node ? "NODE" : "USER";
	my $sort = "    ";
	if ($dxchan->is_node) {
		$sort = "DXSP" if $dxchan->is_spider;
		$sort = "CLX " if $dxchan->is_clx;
		$sort = "DXNT" if $dxchan->is_dxnet;
		$sort = "AR-C" if $dxchan->is_arcluster;
		$sort = "AK1A" if $dxchan->is_ak1a;
	}
	my $name = $dxchan->user->name || " ";
	my $ping = $dxchan->is_node && $dxchan != $DXProt::me ? sprintf("%8.2f", $dxchan->pingave) : "";
	push @out, sprintf "%10s $type $sort $t %-18.18s $ping", $call, $name;
}

return (1, @out)
