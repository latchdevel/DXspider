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
my @out;
my $loc;

#$DB::single = 1;

if ($self->state eq "prompt") {

	my @f = split /\s+/, $line;

	# any thing after send?
	return (1, $self->msg('e6')) if !@f;
  
	$f[0] = uc $f[0];
  
	# first deal with copies
	if ($f[0] eq 'C' || $f[0] eq 'CC' || $f[0] eq 'COPY') {
		my $i = 1;
		my $rr = '0';
		if (uc $f[$i] eq 'RR') {
			$rr = '1';
			$i++;
		}
		my $oref = DXMsg::get($f[$i]);
		#return (0, $self->msg('esend1', $f[$i])) if !$oref;
		#return (0, $self->msg('esend2')) if $i+1 >  @f;
		return (0, "msgno $f[$i] not found") if !$oref;
		return (0, "need a callsign") if $i+1 >  @f;
      
		# separate copy to everyone listed
		for ($i++ ; $i < @f; $i++) {
			my $msgno = DXMsg::next_transno('Msgno');
			my $newsubj = "CC: " . $oref->subject;
			my $nref = DXMsg->alloc($msgno, 
									uc $f[$i], 
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
			push @out, $self->msg('m2', $oref->msgno, $to);
#			push @out, "copy of msg $oref->{msgno} sent to $to";
		}
		DXMsg::queue_msg();
		return (1, @out);
	}

	# now deal with real message inputs 
	# parse out send line for various possibilities
	$loc = $self->{loc} = {};
  
	my $i = 0;
	$f[0] = uc $f[0];
	$loc->{private} = '1';
	if ($f[0] eq 'B' || $f[0] =~ /^NOP/oi) {
		$loc->{private} = '0';
		$i += 1;
	} elsif ($f[0] eq 'P' || $f[0] =~ /^PRI/oi) {
		$i += 1;
	}
  
	$loc->{rrreq} = '0';
	if (uc $f[$i] eq 'RR') {
		$loc->{rrreq} = '1';
		$i++;
	}
  
	# check we have some callsigns
	if ($i  >=  @f) {
		delete $self->{loc};
		return (1, $self->msg('e6'));
	}
  
	# now save all the 'to' callsigns for later
	# first check the 'to' addresses for 'badness'
    my $t;
	my @to;
	foreach  $t (@f[ $i..$#f ]) {
		$t = uc $t;
		if (grep $_ eq $t, @DXMsg::badmsg) {
#			push @out, "Sorry, $t is an unacceptable TO address";
			push @out, $self->msg('m3', $t);
		} else {
			push @to, $t;
		}
	}
	if (@to) {
		$loc->{to} = \@to;
	} else {
		return (1, @out);
	}

	# find me and set the state and the function on my state variable to
	# keep calling me for every line until I relinquish control
	$self->func("DXMsg::do_send_stuff");
	$self->state('send1');
	push @out, $self->msg('m1');
	#push @out, "Enter Subject (30 characters) >";
}

return (1, @out);
