#
# show the channel status
#
# $Id$
#

my $self = shift;
#return (0) if ($self->priv < 9); # only console users allowed
my @list = split;		  # generate a list of callsigns
@list = ($self->call) if !@list;  # my channel if no callsigns

my $call;
my @out;
foreach $call (@list) {
  my $ref = DXChannel->get($call);
  return (0, "Channel: $call not found") if !$ref;

  my @fields = $ref->fields;
  my $field;
  push @out, "User Information $call";
  foreach $field (@fields) {
    my $prompt = $ref->field_prompt($field);
    my $val = $ref->{$field};
    push @out, "$prompt: $val";
  } 
}

return (1, @out);


