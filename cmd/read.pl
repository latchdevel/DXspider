#
# read a message
#
# Copyright (c) Dirk Koopman G1TLH
#
# $Id$
#

my ($self, $line) = @_;
my @f = split /\s+/, $line;
my $msgno;
my @out;
my @body;
my $ref;

# if there are no specified message numbers, try and find a private one
# that I haven't read yet
if (@f == 0) {
  foreach $ref (DXMsg::get_all()) {
	if ($ref->to eq $self->call && $ref->private && !$ref->read) {
	  push @f, $ref->msgno;
	  last;
	}
  }
}

return (1, "Sorry, no new messages for you") if @f == 0;

for $msgno (@f) {
  $ref = DXMsg::get($msgno);
  if (!$ref) {
    push @out, "Msg $msgno not found";
	next;
  }
  if ($self->priv < 5 && $ref->private && $ref->to ne $self->call && $ref->from ne $self->call ) {
    push @out, "Msg $msgno not available";
	next;
  }
  push @out, sprintf "Msg: %d From: %s Date: %6.6s %5.5s Subj: %-30.30s", $msgno,
                     $ref->from, cldate($ref->t), ztime($ref->t), $ref->subject;
  @body = $ref->read_msg_body;
  push @out, @body;
  
  # mark my privates as read
  if ($ref->private && $self->call eq $ref->to && $ref->read == 0) {
    $ref->read(1);
    $ref->store(\@body);    # note call by reference!
  }
  
  # remember this one as the last one read
  $self->lastread($msgno);
}

return (1, @out);
