#
# print out the general log file for announces only
#
# Copyright (c) 1998 - Dirk Koopman G1TLH
#
#
#
my $self = shift;

# this appears to be a reasonable thing for users to do (thank you JE1SGH)
# return (1, $self->msg('e5')) if $self->priv < 9;

my $cmdline = shift;
my @f = split /\s+/, $cmdline;
my $f;
my @out;
my ($from, $to, $who); 

$from = 0;
while ($f = shift @f) {                 # next field
	#  print "f: $f list: ", join(',', @list), "\n";
	if (!$from && !$to) {
		($from, $to) = $f =~ /^(\d+)-(\d+)$/o;         # is it a from -> to count?
		next if $from && $to > $from;
	}
	if (!$to) {
		($to) = $f =~ /^(\d+)$/o if !$to;              # is it a to count?
		next if $to;
	}
	next if $who;
	if ($f !~ /^\d+/) {
		($who) = $f;
	}
	if ($f !~ /^\d+/) {
		($who) = $f;
	}
	#($who) = $f =~ /^(\w+)/o;
}

$to = 20 unless $to;
$from = 0 unless $from;

# if we can get it out of the cache than do it
if (!$who && !$from && $to < @AnnTalk::anncache) {
	my @in = @AnnTalk::anncache[-$to .. -1];
	for (@in) {
		push @out, DXLog::print_item($_);
	}
	return (1, @out);
}

return (1, DXLog::print($from, $to, $main::systime, 'ann', $who)) if $self->{_nospawn} || $DB::VERSION;
return (1, $self->spawn_cmd("show/announce $cmdline", \&DXLog::print, args => [$from, $to, $main::systime, 'ann', $who]));
	
return (1, @out);
