#
# links : which are active
# a complete list of currently connected linked nodes
#
# Created by Iain Philipps G0RDI, based entirely on
# who.pl, which is Copyright (c) 1999 Dirk Koopman G1TLH
# and subsequently plagerized by K1XX.
#
# 16-Jun-2000
# $Id: links.pl
#

my $self = shift;
my $dxchan;
my @out;
my $nowt = time;

push @out, "                                      Ave   Obs   Ping   Sec Since";
push @out, "  Callsign Type Started               RTT  count  Int.   Last Ping";

foreach $dxchan ( sort {$a->call cmp $b->call} DXChannel::get_all() ) {
	next if $dxchan->is_user;
	my $call = $dxchan->call();
	next if $dxchan == $main::me;
	my $t = cldatetime($dxchan->startt);
	my $sort;
	my $name = $dxchan->user->name || " ";
	my $obscount = $dxchan->nopings;
	my $lastt = $nowt - ($dxchan->lastping);
	my $pingint = $dxchan->pingint;
	my $ping = $dxchan != $main::me ? sprintf("%8.2f",$dxchan->pingave) : "";
	$sort = 'ANEA' if $dxchan->is_aranea;
	$sort = "DXSP" if $dxchan->is_spider;
	$sort = "CLX " if $dxchan->is_clx;
	$sort = "DXNT" if $dxchan->is_dxnet;
	$sort = "AR-C" if $dxchan->is_arcluster;
	$sort = "AK1A" if $dxchan->is_ak1a;
	push @out, sprintf "%10s $sort $t$ping    $obscount   %5d       %5d", $call, $pingint, $lastt;
}

return (1, @out)




