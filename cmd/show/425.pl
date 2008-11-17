#
# Query the 425 Database server for a callsign
#
# from an idea by Leo,IZ5FSA and 425DxNews Group
#
#
#
my ($self, $line) = @_;
my @list = map {uc} split /\s+/, $line;               # generate a list of callsigns
my $op;
my $call = $self->call;
my @out;

return (1, $self->msg('e24')) unless $Internet::allow;
return (1, "SHOW/425 <callsign>\nSHOW/425 CAL\nSHOW/425 BULL <bulletin number>\n e.g. SH/425 IQ5BL, SH/425 CAL, SH/425 BUL 779\n") unless @list;

my $target = "www.ariscandicci.it";
my $port = 80;
my $url = "http://www.ariscandicci.it";

use Net::Telnet;
my $t = new Net::Telnet;
eval {$t->open( Host     => $target,
                Port     => $port,
                Timeout  => 30);
};

if (!$t || $@) {
        push @out, $self->msg('e18', 'Open(ARI.org)');
} else {
        dbg($list[0]."|".$list[1]) if isdbg('425');
        if ($list[0] eq "CAL") {
                $op="op=cal";
        }
        elsif ($list[0] eq "BULL") {
                $op="op=bull&query=".$list[1];
        }
        else {
                $op="op=search&query=".$list[0];
        }
	my $s = "GET /425dxn/spider.php?$op HTTP/1.1\n"
        ."User-Agent:DxSpider;$main::version;$main::build;$^O;$main::mycall;$call;$list[0]\nHost: $target\n\n";
        dbg($s) if isdbg('425');
        $t->print($s);
        Log('call', "$call: show/425 \U$op");
        my $state = "blank";
        my $count = 1;
		my @timeout = qw(Timeout 30);
        while (my $result = eval { $t->getline(@timeout) } || $@) {
                dbg($result) if isdbg('425') && $result;
                dbg($@) if isdbg('425') && $@;
                ++$count;
                if ($count > 9) {
						last if $@;
                        push @out, $result;
                }
				@timeout = qw(Timeout 2);
        }
        $t->close;
        push @out, $self->msg('e3', 'Search(ARI.org)', uc $op) unless @out;
}

return (1, @out);
