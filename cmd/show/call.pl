#
# Query the PineKnot Database server for a callsign
#
# from an idea by Steve Franke K9AN and information from Angel EA7WA
#
# $Id$
#
my ($self, $line) = @_;
my @list = split /\s+/, $line;		      # generate a list of callsigns
my $l;
my @out;

return (1, "SHOW/CALL <callsign>, e.g. SH/CALL g1tlh") unless @list;

use Net::Telnet;

my $t = new Net::Telnet;

push @out, $self->msg('call1', 'AA6HF');
foreach $l (@list) {
	$t->open(Host     =>  "jeifer.pineknot.com",
			 Port     =>  1235,
			 Timeout  =>  5);
	if ($t) {
		$t->print(uc $l);
		Log('call', "show/call $l");
		while (my $result = $t->getline) {
			push @out,$result;
		}
		$t->close;
	} else {
		push @out, $self->msg('e18', 'AA6HF');
	}
}

return (1, @out);
