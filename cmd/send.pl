#
# send a message
#
# this should handle
#
# send <call> [<call> .. ]
# send private <call> [<call> .. ]
# send private rr <call> [<call> .. ]
# send rr <call> [<call> .. ]
# send noprivate <call> [<call> .. ]
# send b <call> [<call> .. ]
# send copy <call> [<call> .. ]
# send copy rr <call> [<call> .. ]
# 
# Copyright (c) Dirk Koopman G1TLH
#
# $Id$
#
my ($self, $line) = @_;
return (1, $self->msg('e5')) if $self->remotecmd;

my @out;
my $loc = $self->{loc} = {};
my $notincalls = 1;
my @to;

# set up defaults
$loc->{private} = '1';
$loc->{rrreq} = '0';

# $DB::single = 1;

if ($self->state eq "prompt") {

	my @f = split /\s+/, $line;

	# any thing after send?
	return (1, $self->msg('e6')) if !@f;

	while (@f) {
		my $f = uc shift @f; 

		# first deal with copies
		if ($f eq 'C' || $f eq 'CC' || $f eq 'COPY') {
			my $rr = '0';
			if (@f && uc $f[0] eq 'RR') {
				shift @f;
				$rr = '1';
			}
			
			if (@f) {
				my $m = shift @f;
				my $oref = DXMsg::get($m);
				return (0, $self->msg('m4', $m)) unless $oref;
				return (0, $self->msg('m16')) unless @f;
			
				# separate copy to everyone listed
				while (@f) {
					my $newcall = uc shift @f;
					my $msgno = DXMsg::next_transno('Msgno');
					my $newsubj = "CC: " . $oref->subject;
					my $nref = DXMsg->alloc($msgno, 
											$newcall, 
											$self->call,  
											$main::systime, 
											'1',  
											$newsubj, 
											$main::mycall,
											'0',
											$rr);
					my @list;
					my $from = $oref->from;
					my $to = $oref->to;
					my $date = cldate($oref->t);
					my $time = ztime($oref->t);
					my $buf = "Original from: $from To: $to Date: $date $time";
					push @list, $buf; 
					push @list, $oref->read_msg_body();
					$nref->store(\@list);
					$nref->add_dir();
					push @out, $self->msg('m2', $oref->msgno, $newcall);
				} 
			}
			DXMsg::queue_msg();
			return (1, @out);
		}

		# private / noprivate / rr
		if ($notincalls && ($f eq 'B' || $f =~ /^NOP/oi)) {
			$loc->{private} = '0';
		} elsif ($notincalls && ($f eq 'P' || $f =~ /^PRI/oi)) {
			;
		} elsif ($notincalls && ($f eq 'RR')) {
			$loc->{rrreq} = '1';
		} elsif ($f eq '<' && @f) {     # this is bbs syntax  for from call
			$loc->{from} = uc shift @f;
		} elsif ($f eq '@' && @f) {       # this is bbs syntax, for origin
			$loc->{origin} = uc shift @f;
		} elsif ($f =~ /^\$/) {     # this is bbs syntax  for a bid
			next;
		} elsif ($f =~ /^<\S+/) {     # this is bbs syntax  for from call
			($loc->{from}) = $f =~ /^<(\S+)$/;
		} elsif ($f =~ /^\@\S+/) {     # this is bbs syntax  for origin
			($loc->{origin}) = $f =~ /^\@(\S+)$/;
		} else {

			# callsign ?
			$notincalls = 0;

			# is this callsign a distro?
			my $fn = "/spider/msg/distro/$f.pl";
			if (-e $fn) {
				my $fh = new IO::File $fn;
				if ($fh) {
					local $/ = undef;
					my $s = <$fh>;
					$fh->close;
					my @call;
					@call = eval $s;
					return (1, "Error in Distro $f.pl:", $@) if $@;
					if (@call > 0) {
						push @f, @call;
						next;
					}
				}
			}

			if (grep $_ eq $f, @DXMsg::badmsg) {
				push @out, $self->msg('m3', $f);
			} else {
				push @to, $f;
			}
		}
	}

	# check we have some callsigns
	if (@to) {
		$loc->{to} = \@to;
	} else {
		delete $self->{loc};
		return (1, $self->msg('e6'));
	}

	# find me and set the state and the function on my state variable to
	# keep calling me for every line until I relinquish control
	$self->func("DXMsg::do_send_stuff");
	$self->state('send1');
	push @out, $self->msg('m1');
}

return (1, @out);
