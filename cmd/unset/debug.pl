#
# add a debug level
#
# $Id$
#

use DXDebug;

$self = shift;
return (0) if $self->priv < 9;

dbgsub(split);
my $set = join ' ', dbglist();

return (1, "Debug Levels now: $set"); 
