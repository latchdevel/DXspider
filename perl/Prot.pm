#
# Base class for OO version of all protocol stuff
#

package Prot;

use strict;

sub new
{
	my $pkg = shift;
	my $self = bless {}, $pkg;
	return $self;
}


1;
__END__
