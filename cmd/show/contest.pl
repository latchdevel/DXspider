# contest.pl - contest calendar from www.sk3bg.se/contest
# used with 1 argument: sh/contest <yearandmonth>
# e g sh/contest 2002sep
# Tommy Johansson (SM3OSM) 2002-07-23
# New version using Net::Telnet  2003-03-09
#
# $Id$
#

my ($self, $line) = @_;

return (1, "usage: sh/contest  <year_and_month>, e g sh/contest 2002sep ") unless $line;

my @out;

my $mon;;

# trying to make the syntax abit more user friendly...
# and yes, I have been here and it *is* all my fault (dirk)
$line = lc $line;
my ($m,$y) = $line =~ /^([a-z]{3})\w*\s*(\d+)/;
($y,$m) = $line =~ /^(\d+)\s*([a-z]{3})/ unless $y && $m;
$y += 2000 if $y <= 50;
$y += 1900 if $y > 50 && $y <= 99;
$m = 'oct' if $m eq 'okt';
$m = 'may' if $m eq 'mai' || $m eq 'maj';
$mon = "$y$m";

dbg($mon);

my $filename = "c" . $mon . ".txt";
my $host = 'www.sk3bg.se';
my $port = 80;
my $url = "http://www.sk3bg.se/contest/text/$filename";

my $t = new Net::Telnet (Telnetmode => 0);
eval {
    $t->open(Host => $host, Port => $port, Timeout => 15);
    };

if (!$t || $@) {
    push @out, $self->msg('e18','sk3bg.se');
} else {
    my $s = "GET http://www.sk3bg.se/contest/text/$filename";
    $t->print($s);
    my $notfound = $t->getline(Timeout => 10);
    if ($notfound =~ /404 Object Not Found/) {
	    return (1, "there is no contest info for $mon")
	} else {
	    push @out, $notfound;
	}
    while (!$t->eof) {
    	eval { 
	    push @out, $t->getline(Timeout => 10);
	};
	if ($@) {
	    push @out, $self->msg('e18', 'sk3bg.se');
	    last;    
	}
    }
}
$t->close;

return (1, @out);
