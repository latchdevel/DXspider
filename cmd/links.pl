#
# links : which are active
# a complete list of currently connected linked nodes
#
# Created by Iain Philipps G0RDI, based entirely on
# who.pl, which is Copyright (c) 1999 Dirk Koopman G1TLH
#
# 16-Jun-2000
# $Id: links.pl


my $self = shift;
my $dxchan;
my @out;

push @out, "  Callsign   Started                 Ave RTT";

foreach $dxchan ( sort {$a->call cmp $b->call} DXChannel::get_all_ak1a ) {
	my $call = $dxchan->call();
	my $t = cldatetime($dxchan->startt);
	my $name = $dxchan->user->name || " ";
	my $ping = $dxchan->is_node && $dxchan != $DXProt::me ? sprintf("%8.2f",
																	$dxchan->pingave) : "";
	push @out, sprintf "%10s $t %-6.6s $ping", $call;

}

return (1, @out)




