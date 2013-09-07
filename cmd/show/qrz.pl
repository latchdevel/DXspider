#
# Query the QRZ Database server for a callsign
#
# from an idea by Steve Franke K9AN and information from Angel EA7WA
# and finally (!) modified to use the XML interface
#
# Then made asyncronous...
#
# Copyright (c) 2001-2013 Dirk Koopman G1TLH
#

sub _send
{
	my $conn = shift;
	my $msg = shift;
	my $dxchan = shift;

	my ($tag, $data) = $msg =~ m|^\s*<(\w+)>(.*)</|;
	my $prefix = $conn->{prefix} || ' ';
	$dxchan->send($prefix . sprintf("%-10s: $data", $tag));
}

sub filter
{
	my $conn = shift;
	my $msg = shift;
	my $dxchan = shift;

	my $state = $conn->{state};
	
	dbg("qrz: $state $msg") if isdbg('qrz');

	if ($state eq 'blank') { 
		if ($msg =~ /^<Callsign>/) {
			$conn->{state} = 'go';
		} elsif ($msg =~ /^<Error>/) {
			_send($conn, $msg, $dxchan);
		}
	} elsif ($state eq 'go') {
		return if $msg =~ m|<user>|;
		return if $msg =~ m|<u_views>|;
		return if $msg =~ m|<locref>|;
		return if $msg =~ m|<ccode>|;
		return if $msg =~ m|<dxcc>|;
	    if ($msg =~ m|</Callsign>|) {
			$conn->{state} = 'skip';
			return;
		}
#		$DB::single = 1;
		_send($conn, $msg, $dxchan);
	}
}

sub handle
{
	my ($self, $line) = @_;
	my $call = $self->call;
	my @out;

	return (1, $self->msg('e24')) unless $Internet::allow;
	return (1, "SHOW/QRZ <callsign>, e.g. SH/QRZ g1tlh") unless $line;
	my $target = $Internet::qrz_url || 'xml.qrz.com';
	my $port = 80;
	my $path = qq{/xml?callsign=$line;username=$Internet::qrz_uid;password=$Internet::qrz_pw;agent=dxspider};
	dbg("qrz: $path") if isdbg('qrz');

	Log('call', "$call: show/qrz \U$line");
	my $conn = AsyncMsg->get($self, $target, $port, $path, filter=>\&filter, prefix=>'qrz> ');
	if ($conn) {
		$conn->{state} = 'blank';
		push @out, $self->msg('m21', "show/qrz");
	} else {
		push @out, $self->msg('e18', 'QRZ.com');
	}

	return (1, @out);
}
