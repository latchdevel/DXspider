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

push @out, "  Callsign Type Started           Name              Ave RTT";

foreach $dxchan ( sort {$a->call cmp $b->call} DXChannel::get_all ) {
    my $call = $dxchan->call();
	my $t = cldatetime($dxchan->user->lastin);
	my $sort = $dxchan->is_ak1a() ? "NODE" : "USER";
	my $name = $dxchan->user->name || " ";
	my $ping = $dxchan->is_ak1a ? sprintf("%6.2f", $dxchan->pingave) : "";
	$ping = "" if $dxchan->call eq $main::mycall;
	push @out, sprintf "%10s $sort $t %-18.18s $ping", $call, $name;
}

return (1, @out)
