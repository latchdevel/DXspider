#
# Query the QRZ Database server for a callsign
#
# from an idea by Steve Franke K9AN and information from Angel EA7WA
#
# $Id$
#
my ($self, $line) = @_;
my @list = split /\s+/, $line;		      # generate a list of callsigns
my $l;
my $call = $self->call;
my @out;

return (1, $self->msg('e24')) unless $Internet::allow;
return (1, "SHOW/QRZ <callsign>, e.g. SH/QRZ g1tlh") unless @list;

use Net::Telnet;

my $t = new Net::Telnet;

foreach $l (@list) {
	$t->open(Host     =>  "qrz.com",
			 Port     =>  80,
			 Timeout  =>  15);
	if ($t) {
		my $s = "GET /dxcluster.cgi?callsign=$l\&uid=$Internet::qrz_uid\&pw=$Internet::qrz_pw HTTP/1.0\n\n";
#		print $s;
		$t->print($s);
		Log('call', "$call: show/qrz \U$l");
		my $state = "blank";
		while (my $result = $t->getline) {
#			print $result;
			if ($state eq 'blank' && $result =~ /^\s*Callsign\s*:/i) {
				$state = 'go';
			} elsif ($state eq 'go') {
				next if $result =~ /^\s*Usage\s*:/i;
				chomp $result;
				push @out, $result;
			}
		}
		$t->close;
	} else {
		push @out, $self->msg('e18', 'QRZ.com');
	}
}

return (1, @out);
