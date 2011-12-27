# contest.pl - contest calendar from www.sk3bg.se/contest
# used with 1 argument: sh/contest <yearandmonth>
# e g sh/contest 2002sep
# Tommy Johansson (SM3OSM) 2002-07-23
# New version using Net::Telnet  2003-03-09
#
#
#

my ($self, $line) = @_;

#return (1, "usage: sh/contest  <year_and_month>, e g sh/contest 2002sep ") unless $line;

my @out;

my $mon;

# trying to make the syntax abit more user friendly...
# and yes, I have been here and it *is* all my fault (dirk)
$line = lc $line;
my ($m,$y) = $line =~ /^([a-z]+)\s*(\d+)/;
($y,$m) = $line =~ /^(\d+)\s*([a-z]+)/ unless $y && $m;
unless ($y && $m) {
	($m,$y) = (gmtime)[4,5];
	$m = lc $DXUtil::month[$m];
	$y += 1900;
}
$y += 2000 if $y <= 50;
$y += 1900 if $y > 50 && $y <= 99;
$m = substr $m, 0, 3 if length $m > 3;
$m = 'oct' if $m eq 'okt';
$m = 'may' if $m eq 'mai' || $m eq 'maj';
$mon = "$y$m";

dbg($mon) if isdbg('contest');

my $filename = "c" . $mon . ".txt";
my $host = $Internet::contest_host || 'www.sk3bg.se';
my $port = 80;
my $url = $Internet::contest_url || "http://www.sk3bg.se/contest/text";
$url .= "/$filename";

push @out,  $self->msg('http1', 'sk3bg.se', "$filename");

$self->http_get($host, $url, sub
				{
					my ($response, $header, $body) = @_;
					my @out;

					if ($response =~ /^4/) {
						push @out, "There is no contest info $mon";
					} elsif ($response =~ /^5/) {
						push @out, $self->msg('e18','sk3bg.se');
					} else {
						push @out, split /\r?\n/, $body;
					}
					$self->send_ans(@out);
				}
			   );

return (1, @out);
