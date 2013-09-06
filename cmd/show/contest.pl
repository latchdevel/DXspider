# contest.pl - contest calendar from www.sk3bg.se/contest
# used with 1 argument: sh/contest <yearandmonth>
# e g sh/contest 2002sep
# Tommy Johansson (SM3OSM) 2002-07-23
# New version using Net::Telnet  2003-03-09
#
#
#

my ($self, $line) = @_;

#return (1, "usage: sh/contest [<month>] [<year>], e g sh/contest sep 2012") unless $line;

my @out;

my $mon;;

#$DB::single = 1;


# trying to make the syntax abit more user friendly...
# and yes, I have been here and it *is* all my fault (dirk)
$line = lc $line;
my ($m,$y);
($y) = $line =~ /(\d+)/;
($m) = $line =~ /([a-z]{3})/;

unless ($y) {
	($y) = (gmtime)[5];
	$y += 1900;
}
unless ($m) {
	($m) = (gmtime)[4];
	$m = lc $DXUtil::month[$m];
}
$y += 2000 if $y <= 50;
$y += 1900 if $y > 50 && $y <= 99;
$m = substr $m, 0, 3 if length $m > 3;
$m = 'oct' if $m eq 'okt';
$m = 'may' if $m eq 'mai' || $m eq 'maj';
$mon = "$y$m";

dbg("sh/contest: month=$mon") if isdbg('contest');

my $filename = "c" . $mon . ".txt";
my $host = $Internet::contest_host || 'www.sk3bg.se';
my $port = 80;

dbg("sh/contest: host=$host:$port") if isdbg('contest');

my $url = $Internet::contest_url || "/contest/text";
$url .= "/$filename";

dbg("sh/contest: url=$url") if isdbg("contest");

my $t = new Net::Telnet (Telnetmode => 0);
eval { $t->open(Host => $host, Port => $port, Timeout => 15); };

if (!$t || $@) {
    push @out, $self->msg('e18','sk3bg.se');
} else {
    my $s = "GET $url HTTP/1.0";
	dbg("sh/contest: get='$s'") if isdbg('contest');
	
    $t->print($s);
	$t->print("Host: $host\n");
	$t->print("\n\n");

    my $notfound = $t->getline(Timeout => 10);
    if (!$notfound || $notfound =~ /404 Object Not Found/) {
	    push @out, "there is no contest info for $mon at $host/$url";
		return (1, @out);
	} else {
	    push @out, $notfound;
	}
    while (!$t->eof) {
		eval { push @out, $t->getline(Timeout => 10); };
		if ($@) {
			push @out, $self->msg('e18', 'sk3bg.se');
			last;
		}
    }
}
$t->close;

return (1, @out);
