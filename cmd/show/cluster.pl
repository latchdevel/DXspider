#
# show some statistics
#

my $self = shift;

my ($nodes, $tot, $users, $maxlocalusers, $maxusers, $uptime, $localnodes) = Route::cluster();

return (1, $self->msg('cluster', $localnodes, $nodes, $users, $tot, $maxlocalusers, $maxusers, $uptime));
