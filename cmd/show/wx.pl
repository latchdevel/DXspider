#
# show wx data
#
my $self = shift;

# this appears to be a reasonable thing for users to do (thank you JE1SGH)
# return (1, $self->msg('e5')) if $self->priv < 9;

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
		($to) = $f =~ /^(\d+)$/o if !$to;              # is it a to count?
		next if $to;
	}
}

$to = 20 unless $to;
$from = 0 unless $from;

@out = $self->spawn_cmd(\&DXLog::print, args => [$from, $to, $main::systime, 'ann', 'WX']);
	
#@out = DXLog::print($from, $to, $main::systime, 'ann', $who);
return (1, @out);
