#
# print out the wwv stats
#
# Copyright (c) 1998 - Dirk Koopman G1TLH
#
# $Id$
#
my $self = shift;

my $cmdline = shift;
my @f = split /\s+/, $cmdline;
my $f;
my @out;
my ($from, $to); 

$from = 0;
while ($f = shift @f) {                 # next field
	#  print "f: $f list: ", join(',', @list), "\n";
	if (!$from && !$to) {
		($from, $to) = $f =~ /^(\d+)-(\d+)$/o;         # is it a from -> to count?
		next if $from && $to > $from;
	}
	if (!$to) {
		($to) = $f =~ /^(\d+)$/o;              # is it a to count?
		next if $to;
	}
}

$to = 10 if !$to;

push @out, "Date        Hour   SFI   A   K Forecast                               Logger";
push @out,  Geomag::print($from, $to, $main::systime);
return (1, @out);
