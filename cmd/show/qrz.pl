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

return (1, "SHOW/QRZ <callsign>, e.g. SH/QRZ g1tlh") unless @list;

use Net::Telnet;

my $t = new Net::Telnet;

push @out, $self->msg('call1', "QRZ.com");
foreach $l (@list) {
	$t->open(Host     =>  "qrz.com",
			 Port     =>  80,
			 Timeout  =>  5);
	if ($t) {
		$t->print("GET /database?callsign=$l HTTP/1.0\n\n");
		Log('call', "$call: show/qrz \U$l");
		my $state = "call";
		while (my $result = $t->getline) {
#			print "$state: $result";
			if ($state eq 'call' && $result =~ /$l/i) {
				$state = 'getaddr';
				push @out, uc $l;
			} elsif ($state eq 'getaddr' || $state eq 'inaddr') {
				if ($result =~ /^\s+([\w\s.,;:-]+)(?:<br>)?$/) {
					my $line = $1;
					unless ($line =~ /^\s+$/) {
						push @out, $line;
						$state = 'inaddr' unless $state eq 'inaddr';
					}
				} else {
					$state = 'runout' if $state eq 'inaddr';
				}
			}
		}
		$t->close;
	} else {
		push @out, $self->msg('e18', 'QRZ.com');
	}
}

return (1, @out);
