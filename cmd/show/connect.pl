#
# show active connections
#
# Copyright (c) 2001 Dirk Koopman G1TLH
#
# $Id$
#

my $self = shift;
return (1, $self->msg('e5')) if $self->priv < 1;
my @out;
my $count;

push @out, "Cnum Call      Address/Port              State  Type   Dir.";

foreach my $call (sort keys %Msg::conns) {
	my $r = $Msg::conns{$call};
	my $addr = "$r->{peerhost}/$r->{peerport}";
	my $c = $call;
	if ($c =~ /^Server\s+(\S+)$/) {
		$addr = $1;
		$c = "Server";
	}
	push @out, 	sprintf(" %3d %-9s %-27.27s %3s %7s %8s", 
						$r->{cnum}, $c, 
						$addr, $r->{state}, 
						$r->{csort}, $r->{sort});

	$count++;
}
push @out, "$count Connections";
return (1, @out);
