#
# kill or delete a message
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
my $call = $self->call;
my $full;

if ($f[0] =~ /^f/io) {
	return (1, $self->msg('e5')) if $self->priv < 5;
	$full = 1;
	shift @f;
}

# $DB::single = 1;

for $msgno (@f) {
  $ref = DXMsg::get($msgno);
  if (!$ref) {
    push @out, "Msg $msgno not found";
	next;
  }
  if ($self->priv < 5 && 
      (($ref->private && $ref->to ne $self->call && $ref->from ne $self->call) ||
      ($ref->private == 0  && $ref->from ne $self->call))) {
    push @out, "Msg $msgno not available";
	next;
  } 
  Log('msg', "Message $ref->{msgno} from $ref->{from} to $ref->{to} deleted by $call");
  if ($full) {
	  DXProt::broadcast_ak1a(DXProt::pc49($self->call, $ref->{subject}), $DXProt::me);
  }
  $ref->del_msg;
  push @out, "Message $msgno deleted";
}

return (1, @out);
