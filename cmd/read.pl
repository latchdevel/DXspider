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

for $msgno (@f) {
  $ref = DXMsg::get($msgno);
  if (!$ref) {
    push @out, "Msg $msgno not found";
	next;
  }
  if ($ref->private && $self->priv < 9 && $ref->to ne $ref->call) {
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
}

return (1, @out);
