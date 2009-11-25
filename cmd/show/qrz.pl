#
# Query the QRZ Database server for a callsign
#
# from an idea by Steve Franke K9AN and information from Angel EA7WA
# and finally (!) modified to use the XML interface
#
# Copyright (c) 2001-2009 Dirk Koopman G1TLH
#
my ($self, $line) = @_;
my @list = split /\s+/, $line;		      # generate a list of callsigns
my $l;
my $call = $self->call;
my @out;

return (1, $self->msg('e24')) unless $Internet::allow;
return (1, "SHOW/QRZ <callsign>, e.g. SH/QRZ g1tlh") unless @list;
my $target = $Internet::http_proxy || $Internet::qrz_url || 'xml.qrz.com';
my $port = $Internet::http_proxy_port || 80;
my $url = '';
$url = 'http://' . ($Internet::qrz_url | 'xml.qrz.com') if $Internet::http_proxy;


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
		my $s = "GET /xml?callsign=$l;username=$Internet::qrz_uid;password=$Internet::qrz_pw;agent=dxspider HTTP/1.0\n\n";
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
			if ($state eq 'blank' && $result =~ /^<Callsign>/i) {
				$state = 'go';
			} elsif ($state eq 'go') {
				next if $result =~ m|<user>|;
				next if $result =~ m|<u_views>|;
				next if $result =~ m|<locref>|;
				next if $result =~ m|<ccode>|;
				next if $result =~ m|<dxcc>|;
				last if $result =~ m|</Callsign>|;
				my ($tag, $data) = $result =~ m|^\s*<(\w+)>(.*)</|;
				push @out, sprintf "%10s: $data", $tag;
			}
		}
		$t->close;
		push @out, $self->msg('e3', 'qrz.com', uc $l) unless @out;
	}
}

return (1, @out);
