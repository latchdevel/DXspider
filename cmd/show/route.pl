#
# show the routing to a node or station
#
# Copyright (c) 2001 Dirk Koopman G1TLH
#
# $Id$
#

my ($self, $line) = @_;
my @list = map { uc } split /\s+/, $line;           # list of callsigns of nodes
my @out;

return (1, $self->msg('e6')) unless @list;

use RouteDB;

my $l;
foreach $l (@list) {
	my $ref = Route::get($l);
	if ($ref) {
		my $parents = $ref->isa('Route::Node') ? $l : join(',', $ref->parents);
		push @out, $self->msg('route', $l, $parents,  join(',', map {$_->call} $ref->alldxchan));
	} else {
		push @out, $self->msg('e7', $l);
	}
	my @in = RouteDB::_sorted($l);
	if (@in) {
		push @out, "Learned Routes:";
		for (@in) {
			push @out, "$l via $_->{call} count: $_->{count} last heard: " . atime($_->{t});
		}
	}
}

return (1, @out);
