#
# links : which are active
# a complete list of currently connected linked nodes
#
# Created by Iain Philipps G0RDI, based entirely on
# who.pl, which is Copyright (c) 1999 Dirk Koopman G1TLH
#
# 16-Jun-2000
# $Id: links.pl
#

my $self = shift;
my $dxchan;
my @out;

push @out, "  Callsign Type Started            Ave RTT";

foreach $dxchan ( sort {$a->call cmp $b->call} DXChannel::get_all_ak1a ) {
	my $call = $dxchan->call();
	my $t = cldatetime($dxchan->startt);
	my $sort;
	my $name = $dxchan->user->name || " ";
	my $ping = $dxchan->is_node && $dxchan != $DXProt::me ? sprintf("%8.2f",
																	$dxchan->pingave) : "";
	$sort = "DXSP" if $dxchan->is_spider;
	$sort = "CLX " if $dxchan->is_clx;
	$sort = "DXNT" if $dxchan->is_dxnet;
	$sort = "AR-C" if $dxchan->is_arcluster;
	$sort = "AK1A" if $dxchan->is_ak1a;
	push @out, sprintf "%10s $sort $t $ping", $call;
}

return (1, @out)




