#
# show the station details
#
# Copyright (c) 1998 - Dirk Koopman G1TLH
#
# $Id$
#

my ($self, $line) = @_;
my @f = split /\s+/, uc $line;
my @out;
my $call;

if (@f == 0) {
  return (1, "*** no station specified ***") if ($self->priv < 5); 
  my @calls = DXUser::get_all_calls();
  foreach $call (@calls) {
    my $ref = DXUser->get_current($call);
	next if !$ref;
	my $sort = $ref->sort;
	my $qth = $ref->qth;
	my $home = $ref->node;
    push @out, "$call $sort $qth $home";
  }
} else {
  foreach $call (@f) {
    my $ref = DXUser->get_current($call);
	if ($ref) {
	  my $name = $ref->name;  
      my $qth = $ref->qth;
	  my $lat = $ref->lat;
	  my $long = $ref->long;
	  my $node = $ref->node;
#	  my $homenode = $ref->homenode;
	  push @out, "$call $qth $lat $long $node";
	} else {
	  push @out, "$call not known";
	}
  }
}

return (1, @out);
