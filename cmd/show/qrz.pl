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
my $target = $Internet::http_proxy || 'u2.qrz.com';
my $port = $Internet::http_proxy_port || 80;
my $url = '';
$url = 'http://u2.qrz.com' if $Internet::http_proxy; 

use Net::Telnet;

my $t = new Net::Telnet;

foreach $l (@list) {
	eval {
		$t->open(Host     =>  $target,
				 Port     =>  $port,
				 Timeout  =>  15);
	};

	if (!$t || $@) {
		push @out, $self->msg('e18', 'QRZ.com');
	} else {
		my $s = "GET $url/dxcluster.cgi?callsign=$l\&uid=$Internet::qrz_uid\&pw=$Internet::qrz_pw HTTP/1.0\n\n";
		dbg($s) if isdbg('qrz');
		$t->print($s);
		Log('call', "$call: show/qrz \U$l");
		my $state = "blank";
		while (my $result = eval { $t->getline(Timeout => 30) } || $@) {
			dbg($result) if isdbg('qrz') && $result;
			if ($@) {
				push @out, $self->msg('e18', 'QRZ.com');
				last;
			}
			if ($state eq 'blank' && $result =~ /^\s*Callsign\s*:/i) {
				$state = 'go';
			} elsif ($state eq 'go') {
				next if $result =~ /^\s*Usage\s*:/i;
				chomp $result;
				push @out, $result;
			}
		}
		$t->close;
		push @out, $self->msg('e3', 'qrz.com', uc $l) unless @out;
	}
}

return (1, @out);
