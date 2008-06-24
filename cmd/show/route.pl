#
# show the routing to a node or station
#
# Copyright (c) 2001 Dirk Koopman G1TLH
#
#
#

my ($self, $line) = @_;
my @list = map { uc } split /\s+/, $line;           # list of callsigns of nodes
my @out;

return (1, $self->msg('e6')) unless @list;

my $l;
foreach $l (@list) {
	my $ref = Route::get($l);
	if ($ref) {
		my $parents = $ref->isa('Route::Node') ? $l : join(',', $ref->parents);
		push @out, $self->msg('route', $l, $parents,  join(',', map {$_->call} Route::findroutes($l)));
	} else {
		push @out, $self->msg('e7', $l);
	}
}

return (1, @out);
