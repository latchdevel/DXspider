#
# show all the values on a message header
#
# $Id$
#

my ($self, $line) = @_;
my @list = split /\s+/, $line;		      # generate a list of msg nos
my @out;

return (1, $self->msg('e5')) if $self->priv < 5;
return (1, $self->msg('m16')) if @list == 0;

foreach my $msgno (@list) {
  my $ref = DXMsg::get($msgno);
  if ($ref) {
    @out = print_all_fields($self, $ref, "Msg Parameters $msgno");
  } else {
    push @out, $self->msg('m4', $msgno);
  }
  push @out, "" if @list > 1;
}

return (1, @out);
