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
$url = 'http://' . ($Internet::qrz_url || 'xml.qrz.com') if $Internet::http_proxy;

foreach $l (@list) {

	my $host = $url?$url:$target;
	my $s = "$url/xml?callsign=$l;username=$Internet::qrz_uid;password=$Internet::qrz_pw;agent=dxspider";
	if (isdbg('qrz')) {
		dbg("qrz: $host");
		dbg("qrz: $s");
	}

	Log('call', "$call: show/qrz \U$l");
	push @out,  $self->msg('http1', 'qrz.com', "\U$l");

	$self->http_get($host, $s, sub
					{
						my ($response, $header, $body) = @_;
						my @out;

						if (isdbg('qrz')) {
							dbg("qrz response: $response");
							dbg("qrz body: $body");
						}
						if ($response =~ /^5/) {
							push @out, $self->msg('e18',"qrz.com $!");
						} else {
							Log('call', "$call: show/qrz \U$body");
							my $state = "blank";
							foreach my $result (split /\r?\n/, $body) {
								dbg("qrz: $result") if isdbg('qrz') && $result;
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
							if (@out) {
								unshift @out, $self->msg('http2', "show/qrz \U$l");
							} else {
								push @out, $self->msg('e3', 'show/qrz', uc $l);
							}
						}
						$self->send_ans(@out);
					}
				   );
}

return (1, @out);
