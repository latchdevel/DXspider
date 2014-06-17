#
# print out the general log file
#
# Copyright (c) 1998 - Dirk Koopman G1TLH
#
#
#

sub handle
{
	my $self = shift;

	my $cmdline = shift;
	my @f = split /\s+/, $cmdline;
	my $f;
	my @out;
	my ($from, $to, $who, $hint); 
	
	$from = 0;
	while ($f = shift @f) {                 # next field
		#  print "f: $f list: ", join(',', @list), "\n";
		unless ($from || $to) {
			($from, $to) = $f =~ /^(\d+)-(\d+)$/o;         # is it a from -> to count?
			next if $from && $to > $from;
		}
		unless ($to) {
			($to) = $f =~ /^(\d+)$/o if !$to;              # is it a to count?
			next if $to;
		}
		unless ($who) {
			$who = $f; 
			next if $who;
		}
	}

	$to = 20 unless $to;
	$from = 0 unless $from;
	
	if ($self->priv < 6) {
		return (1, $self->msg('e5')) if defined $who && $who ne $self->call;
		$who = $self->call;
	}

	@out = $self->spawn_cmd(\&DXLog::print, args => [$from, $to, $main::systime, undef, $who]);
	
#	my $fc = Mojo::IOLoop::ForkCall->new;
#	$fc->run(
#			 sub {my @args = @_; my @res = DXLog::print(@args); return @res}, 
#			 [$from, $to, $main::systime, undef, $who],
#			 sub {my ($fc, $err, @out) = @_; delete $self->{stash}; $self->send(@out);}
#			);
#	#$self->{stash} = $fc;
	
#	@out = DXLog::print($from, $to, $main::systime, undef, $who);
	return (1, @out);
}
