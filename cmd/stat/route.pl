#
# show a Route::Node thingy
#
# Copyright (c) 2001 Dirk Koopman G1TLH
#
# $Id$
#

my ($self, $line) = @_;
my @out;
my @list = split /\s+/, $line;		      # generate a list of callsigns
@list = ($self->call) if !@list;  # my channel if no callsigns
if ($self->priv > 5 && @list && uc $list[0] eq 'ALL') {
	push @out, "Callsigns in Routing Table";
	@list =  Route::get_all();
	my ($ncount, $ucount);
	my $n = int $self->width / 12;
	$n ||= 6;
	while (@list > $n) {
		push @out, join(' ', map {
			$ncount++ if $_->isa('Route::Node'); 
			$ucount++ if $_->isa('Route::User'); 
			sprintf "%9s/%s",$_->call,$_->isa('Route::Node') ? 'N':'U' 
		} splice(@list, 0, $n));
	} 
	push @out, join(' ', map {
		$ncount++ if $_->isa('Route::Node'); 
		$ucount++ if $_->isa('Route::User'); 
		sprintf "%9s/%s",$_->call,$_->isa('Route::Node') ? 'N':'U' 
	} @list) if @list;
	push @out, "$ncount Nodes $ucount Users";
	return (1, @out);
}

my $call;
foreach $call (@list) {
  $call = uc $call;
  my $ref = Route::get($call);
  if ($ref) {
	my $sort = ref $ref;	  
    @out = print_all_fields($self, $ref, "$sort Information $call");
  } else {
    push @out, "Route::Node: $call not found";
  }
  push @out, "" if @list > 1;
}

return (1, @out);
