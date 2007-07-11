#
# links : which are active
# a complete list of currently connected linked nodes
#
# Created by Iain Philipps G0RDI, based entirely on
# who.pl, which is Copyright (c) 1999 Dirk Koopman G1TLH
# and subsequently plagerized by K1XX.
#
# 16-Jun-2000
#
#

my $self = shift;
my $dxchan;
my @out;
my $nowt = time;

push @out, "                                      Ave  Obs  Ping  Next      Filters";
push @out, "  Callsign Type Started               RTT Count Int.  Ping Iso? In  Out PC92?";

foreach $dxchan ( sort {$a->call cmp $b->call} DXChannel::get_all_nodes ) {
	my $call = $dxchan->call();
	next if $dxchan == $main::me;
	my $t = cldatetime($dxchan->startt);
	my $sort;
	my $name = $dxchan->user->name || " ";
	my $obscount = $dxchan->nopings;
	my $lastt = $dxchan->pingint - ($nowt - $dxchan->lastping);
	my $pingint = $dxchan->pingint;
	my $ping = $dxchan->is_node && $dxchan != $main::me ? sprintf("%8.2f",$dxchan->pingave) : "";
	my $iso = $dxchan->isolate ? 'Y' :' ';
	my ($fin, $fout, $pc92) = (' ', ' ', ' ');
	if ($dxchan->do_pc9x) {
		$pc92 = 'Y';
	} else {
		my $f;
		if ($f = $dxchan->inroutefilter) {
			$fin = $dxchan->inroutefilter =~ /node_default/ ? 'D' : 'Y';
		}
		if ($f = $dxchan->routefilter) {
			$fout = $dxchan->routefilter =~ /node_default/ ? 'D' : 'Y';
		}
	}
	$sort = 'ANEA' if $dxchan->is_aranea;
	$sort = "DXSP" if $dxchan->is_spider;
	$sort = "CLX " if $dxchan->is_clx;
	$sort = "DXNT" if $dxchan->is_dxnet;
	$sort = "AR-C" if $dxchan->is_arcluster;
	$sort = "AK1A" if $dxchan->is_ak1a;
	push @out, sprintf "%10s $sort $t$ping   $obscount  %5d %5d  $iso    $fin   $fout   $pc92", $call, $pingint, $lastt;
}

return (1, @out)




