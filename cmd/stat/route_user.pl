#
# show a Route::User thingy
#
# Copyright (c) 2001 Dirk Koopman G1TLH
#
# $Id$
#

my ($self, $line) = @_;
my @list = split /\s+/, $line;		      # generate a list of callsigns
@list = ($self->call) if !@list;  # my channel if no callsigns

my $call;
my @out;
foreach $call (@list) {
  $call = uc $call;
  my $ref = Route::User::get($call);
  if ($ref) {
    @out = print_all_fields($self, $ref, "Route::User Information $call");
  } else {
    push @out, "Route::User: $call not found";
  }
  push @out, "" if @list > 1;
}

return (1, @out);
