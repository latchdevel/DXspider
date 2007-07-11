#
# Query the WM7D Database server for a callsign
#
# Largely based on "sh/qrz" and info in the Net::Telnet documentation
#
# Copyright (c) 2002 Charlie Carroll K1XX
#
#
#

# wm7d accepts only single callsign
my ($self, $line) = @_;
my $call = $self->call;
my @out;

# send 'e24' if allow in Internet.pm is not set to 1
return (1, $self->msg('e24')) unless $Internet::allow;
return (1, "SHOW/WM7D <callsign>, e.g. SH/WM7D k1xx") unless $line;
my $target = $Internet::wm7d_url || 'www.wm7d.net';
my $port = 5000;
my $cmdprompt = '/query->.*$/';

my($info, $t);
                                    
$t = new Net::Telnet;
$info =  $t->open(Host    => $target,
		  Port    => $port,
		  Timeout => 20);

if (!$info) {
	push @out, $self->msg('e18', 'WM7D.net');
} else {
        ## Wait for prompt and respond with callsign.
        $t->waitfor($cmdprompt);
	$t->print($line);
        ($info) = $t->waitfor($cmdprompt);
    
	# Log the lookup
	Log('call', "$call: show/wm7d \U$line");
	$t->close;
	push @out, split /[\r\n]+/, $info;
}
return (1, @out);
