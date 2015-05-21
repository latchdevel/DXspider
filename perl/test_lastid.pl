#!/usr/bin/env perl

my $pc9x_past_age = 3600;
my $pc9x_future_age = 3600*2;
my $lastid;

try($_) for qw(85955 85968 518 85967 519 85968 520 85969), @ARGV;

exit 0;

sub try
{
	my $t = shift;

	print "$t : ";

	if (defined $lastid) {
		if ($t < $lastid) {
			my $wt;
			if (($wt = $t+86400-$lastid) > $pc9x_past_age) {
				print "PCPROT: dup id on $t + 86400 - $lastid ($wt) > $pc9x_past_age, ignored\n";
				return;
			}
			print "wt = $wt ";
		} elsif ($t == $lastid) {
			print "PCPROT: dup id on $t == $lastid, ignored\n";
			return;
		} elsif ($t > $lastid) {
			if ($t - $lastid > $pc9x_future_age) {
				print "PCPROT: dup id $t too far in future on $lastid\n";
				return;
			}
		}
	}

	print "$lastid Ok\n";
	$lastid = $t;
}


