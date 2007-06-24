#
# Dummy Log Agent
#
# This is just for the benefit of Storable on 5.8.0
#
# Copyright (c) Dirk Koopman
#
#
#

package Log::Agent;

use DXDebug;

$VERSION = 0.3;
@ISA = qw(Exporter);
@EXPORT = qw(logcroak logcarp);

sub logcroak
{
	DXDebug::croak(@_);
}

sub logcarp
{
	DXDebug::carp(@_);
}
1;
