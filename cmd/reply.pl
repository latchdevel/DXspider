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
  
  my $oref; 
  
  # check we have a reply number
  if ($i  >  @f) {
    if (!($oref = DXMsg::get($self->lastread))) {
      delete $self->{loc};
      #return (0, $self->msg('esend2'));
      return (0, "need a message number");
	}
  } else {
    $oref = DXMsg::get($f[$i]);
	if (!$oref) {
	  delete $self->{loc};
	  return (0, "can't access message $i");
	}
  }
  
  # now save all the 'to' callsigns for later
  my $to = $oref->from;
  $loc->{to} = [ $to ];       # to is an array
  $loc->{subject} = $oref->subject;
  $loc->{subject} = "Re: " . $loc->{subject} if !($loc->{subject} =~ /^Re:.\s/io); 

  # find me and set the state and the function on my state variable to
  # keep calling me for every line until I relinquish control
  $self->func("DXMsg::do_send_stuff");
  $self->state('sendbody');
  #push @out, $self->msg('sendsubj');
  push @out, "Reply to: $to";
  push @out, "Subject : $loc->{subject}";
  push @out, "Enter Message /EX (^Z) to send or /ABORT (^Y) to exit";
}

return (1, @out);
