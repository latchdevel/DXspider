#
# Query the DB0SDX QSL server for a callsign
#
# Copyright (c) 2003 Dirk Koopman G1TLH
# Modified Dec 9, 2004 for new website and xml schema by David Spoelstra N9KT
# and tidied up by me (Dirk)
#
# $Id$
#

my ($self, $line) = @_;
my $call = $self->call;
my @out;

$line = uc $line;
return (1, $self->msg('e24')) unless $Internet::allow;
return (1, "SHOW/DB0SDX <callsign>, e.g. SH/DB0SDX ea7wa") unless $line && is_callsign($line);
my $target = $Internet::db0sdx_url || 'www.qslinfo.de';
my $path = $Internet::db0sdx_path || '/qslinfo';
my $suffix = $Internet::db0sdx_suffix || '.asmx';
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
    <qslinfo xmlns="http://$target$path">
      <callsign>$line</callsign>
      <ClientInformation>DXSpider V$main::version B$main::build ($call\@$main::mycall)</ClientInformation>
    </qslinfo>
  </soap:Body>
</soap:Envelope>
);
	

	my $lth = length($s)+7;
	
	dbg("db0sdx out: $s") if isdbg('db0sdx');
	
	$t->print("POST $path$suffix HTTP/1.0");
	$t->print("Host: $target");
	$t->print("Content-Type: text/xml; charset=utf-8");
	$t->print("Content-Length: $lth");
	$t->print("Connection: Close");
	$t->print(qq{SOAPAction: "http://$target$path"});
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
