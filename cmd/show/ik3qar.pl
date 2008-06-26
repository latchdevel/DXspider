#
# Query the IK3QAR Database server for a callsign
#
# from an idea by Paolo,IK3QAR and Leo,IZ5FSA
#
# $Id$
#
my ($self, $line) = @_;
my @list = map {uc} split /\s+/, $line;               # generate a list of callsigns
my $op;
my $call = $self->call;
my @out;

return (1, $self->msg('e24')) unless $Internet::allow;
return (1, "SHOW/IK3QAR <callsign>\n  e.g. SH/IK3QAR II5I, SH/IK3QAR V51AS\n") unless @list;

my $target = $Internet::ik3qar_url;
my $port = 80;
my $url = "http://".$target;

use Net::Telnet;
my $t = new Net::Telnet;
eval {$t->open( Host     => $target,
                Port     => $port,
                Timeout  => 30);
};

if (!$t || $@) {
        push @out, $self->msg('e18', 'Open(IK3QAR.it)');
} else {
        dbg($list[0]."|".$list[1]) if isdbg('IK3QAR');
        $op="call=".$list[0]."&node=".$main::mycall."&passwd=".$Internet::ik3qar_pw."&user=".$call;
        my $s = "GET $url/manager/dxc/dxcluster.php?$op HTTP/1.0\n"
       ."User-Agent:DxSpider;$main::version;$main::build;$^O;$main::mycall;$call\n\n";
        dbg($s) if isdbg('IK3QAR');
        $t->print($s);
        Log('call', "$call: SH/IK3QAR $list[0]");
        my $state = "blank";
        my $count = 1;
        while (my $result = eval { $t->getline(Timeout => 30) } || $@) {
                dbg($result) if isdbg('IK3QAR') && $result;
                ++$count;
                if ($count > 9) {
                        push @out, $result;
                }
        }
        $t->close;
        push @out, $self->msg('e3', 'Search(IK3QAR.it)', uc $list[0]) unless @out;
}

return (1, @out);
