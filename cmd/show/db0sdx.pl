#
# Query the DB0SDX QSL server for a callsign
#
# Copyright (c) 2003 Dirk Koopman G1TLH
#
# $Id$
#

my ($self, $line) = @_;
my $call = $self->call;
my @out;

$line = uc $line;
return (1, $self->msg('e24')) unless $Internet::allow;
return (1, "SHOW/DB0SDX <callsign>, e.g. SH/DB0SDX ea7wa") unless $line && is_callsign($line);
my $target = $Internet::db0sdx_url || 'dotnet.grossmann.com';
my $port = 80;
my $cmdprompt = '/query->.*$/';

my($info, $t);
                                    
$t = new Net::Telnet;

dbg("db0sdx: contacting $target:$port") if isdbg('db0sdx');
$info =  $t->open(Host    => $target,
		  Port    => $port,
		  Timeout => 15);

if (!$info) {
	push @out, $self->msg('e18', 'DB0SDX Database server');
} else {

	dbg("db0sdx: connected to $target:$port") if isdbg('db0sdx');

	my $s = qq(<?xml version="1.0" encoding="utf-8"?>
<soap:Envelope xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
  <soap:Body>
    <qslinfo xmlns="http://dotnet.grossmann.com/qslinfo">
      <callsign>$line</callsign>
    </qslinfo>
  </soap:Body>
</soap:Envelope>
);
	

	my $lth = length($s)+7;
	
	dbg("db0sdx out: $s") if isdbg('db0sdx');
	
	$t->print("POST /qslinfo/qslinfo.asmx HTTP/1.0");
	$t->print("Host: dotnet.grossmann.com");
	$t->print("Content-Type: text/xml; charset=utf-8");
	$t->print("Content-Length: $lth");
	$t->print("Connection: Close");
	$t->print("SOAPAction: \"http://dotnet.grossmann.com/qslinfo/qslinfo\"");
	$t->print("");
	$t->put($s);

	my $in;
	
	while (my $result = eval { $t->getline(Timeout => 30) } || $@) {
		if ($@) {
			push @out, $self->msg('e18', 'DB0SDX Server');
			last;
		} else {
			$in .= $result;
		}
	}

 	dbg("db0sdx in: $in") if isdbg('db0sdx');
	
	# Log the lookup
	Log('call', "$call: show/db0sdx $line");
	$t->close;

	my ($info) = $in =~ m|<qslinfoResult>([^<]*)</qslinfoResult>|;
	my @in = split /[\r\n]/, $info if $info;
	if (@in && $in[0]) {
		push @out, @in;
	} else {
		($info) = $in =~ m|<faultstring>([^<]*)</faultstring>|;
		push @out, $info if $info;
		push @out, $self->msg('e3', 'DB0SDX', $line) unless @out;		
	}
}
return (1, @out);
