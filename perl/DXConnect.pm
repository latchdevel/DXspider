#
# module to manage outgoing connections and things
#
# Copyright (c) 1998 - Dirk Koopman G1TLH
#
# $Id$
#

package DXConnect;

@ISA = qw(DXChannel);

use DXUtil;
use DXM;
use DXDebug;

use strict;

use vars qw($VERSION $BRANCH);
$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /\d+\.\d+\.(\d+)\.(\d+)/  || (0,0));
$main::build += $VERSION;
$main::branch += $BRANCH;

sub init
{

}

sub process
{

}

1;
__END__

