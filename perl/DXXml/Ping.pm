#
# XML Ping handler
#
# $Id$
#
# Copyright (c) Dirk Koopman, G1TLH
#

use strict;

package DXXml::Ping;

use DXDebug;
use DXProt;
use IsoTime;

use vars qw($VERSION $BRANCH @ISA);
$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /\d+\.\d+\.(\d+)\.(\d+)/  || (0,0));
$main::build += $VERSION;
$main::branch += $BRANCH;

@ISA = qw(DXXml);

sub handle_input
{
	my $self = shift;
	my $dxchan = shift;
	
}

1;
