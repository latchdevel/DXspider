#
# show the channel status
#
# $Id$
#

my ($self, $line) = @_;
my @list = /\s+/, $line;		  # generate a list of callsigns
@list = ($self->call) if (!@list || $self->priv < 9);  # my channel if no callsigns

my $call;
my @out;
foreach $call (@list) {
  $call = uc $call;
  my $ref = DXChannel->get($call);
  if ($ref) {
    @out = print_all_fields($self, $ref, "Channe Information $call");
  } else {
    return (0, "Channel: $call not found") if !$ref;
  }
  push @out, "" if @list > 1;
}

return (1, @out);


