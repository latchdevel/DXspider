#
# XML DX Spot handler
#
# $Id$
#
# Copyright (c) Dirk Koopman, G1TLH
#

use strict;

package DXXml::Dx;

use DXDebug;
use DXProt;
use IsoTime;

use vars qw(@ISA);
@ISA = qw(DXXml);

sub handle_input
{
	my $self = shift;
	my $dxchan = shift;
	
}

1;
