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
	
	my @f = split /\s+/, $line if $line;
	
	# now deal with real message inputs 
	# parse out send line for various possibilities
	$loc = $self->{loc} = {};
	
	my $i = 0;
	$loc->{private} = '1';
	if ($i < @f) {
		if ($f[0] =~ /^(B|NOP)/oi) {
			$loc->{private} = '0';
			$i += 1;
		} elsif ($f[0] =~ /^P/oi) {
			$i += 1;
		}
	}
	
	if ($i < @f) {
		$loc->{rrreq} = '0';
		if (uc $f[$i] eq 'RR') {
			$loc->{rrreq} = '1';
			$i++;
		}
	}
	my $oref; 
	
	# check we have a reply number
	#  $DB::single = 1;
	
	if ($i < @f) {
		$oref = DXMsg::get($f[$i]);
		if (!$oref) {
			delete $self->{loc};
			return (1, $self->msg('m4', $i));
		}
	} else {
		if (!($oref = DXMsg::get($self->lastread))) {
			delete $self->{loc};
			return (1, $self->msg('m5'));
			#return (1, "need a message number");
		}
	}
	
	# now save all the 'to' callsigns for later
	my $to = $oref->from;
	$loc->{to} = [ $to ];       # to is an array
	$loc->{subject} = $oref->subject;
	$loc->{subject} = "Re: " . $loc->{subject} if !($loc->{subject} =~ /^Re:\s/io); 
	
	# find me and set the state and the function on my state variable to
	# keep calling me for every line until I relinquish control
	$self->func("DXMsg::do_send_stuff");
	$self->state('sendbody');
	#push @out, $self->msg('sendsubj');
#	push @out, "Reply to: $to";
#	push @out, "Subject : $loc->{subject}";
#	push @out, "Enter Message /EX (^Z) to send or /ABORT (^Y) to exit";
	push @out, $self->msg('m6', $to);
	push @out, $self->msg('m7', $loc->{subject});
	push @out, $self->msg('m8');
}

return (1, @out);
