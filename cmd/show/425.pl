#
# Query the 425 Database server for a callsign
#
# from an idea by Leonardo Lastrucci IZ5FSA and information from Mauro I1JQJ
#
# $Id$
#
my ($self, $line) = @_;
my @list = map {uc} split /\s+/, $line;		      # generate a list of callsigns
my $l;
my $call = $self->call;
my @out;

return (1, $self->msg('e24')) unless $Internet::allow;
return (1, "SHOW/425 <callsign>, e.g. SH/425 3B9FR") unless @list;
my $target = $Internet::http_proxy || $Internet::dx425_url || "www.ariscandicci.it";
my $port = $Internet::http_proxy_port || 80;
my $url = '';
$url = 'http://' . ($Internet::dx425_url || 'www.ariscandicci.it'); #  if $Internet::http_proxy; 

use Net::Telnet;

my $t = new Net::Telnet;

foreach $l (@list) {
	eval {
		$t->open(Host     =>  $target,
				 Port     =>  $port,
				 Timeout  =>  15);
	};
	if (!$t || $@) {
		push @out, $self->msg('e18', 'Open(425.org)');
	} else {
		my $s = "GET $url/modules.php?name=425dxn&op=spider&query=$l";
		dbg($s) if isdbg('425');
		$t->print($s);
		Log('call', "$call: show/425 \U$l");
		my $state = "blank";
		while (my $result = eval { $t->getline(Timeout => 30) } || $@) {
			dbg($result) if isdbg('425') && $result;
				chomp $result;
				push @out, $result;
		}
		$t->close;
		push @out, $self->msg('e3', 'Search(425.org)', uc $l) unless @out;
	}
}

return (1, @out);
