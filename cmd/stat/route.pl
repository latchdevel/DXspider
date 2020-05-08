#
# show a Route thingy
#
# Copyright (c) 2020 Dirk Koopman G1TLH
#
# A general purpose Route get thingy, use stat/route_user or _node if
# you want a list of all that particular type of thingy otherwise this
# is likely to be less typing and will dwym.
#

my ($self, $line) = @_;
my @out;
my @list = split /\s+/, $line;		      # generate a list of callsigns

push @list, $self->call unless @list;

foreach my $call (@list) {
  $call = uc $call;
  my $ref = Route::get($call);
  if ($ref) {
    push @out, print_all_fields($self, $ref, "Route::User Information $call");
  } else {
    push @out, "Route: $call not found";
  }
  push @out, "" if @list > 1;
}

return (1, @out);
