#
# Module for SQLite DXSql variants
#
# Stuff like table creates and (later) alters
#
# $Id$
#
# Copyright (c) 2005 Dirk Koopman G1TLH
#

package DXSql::SQLite;

use vars qw($VERSION $BRANCH @ISA);
$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /\d+\.\d+\.(\d+)\.(\d+)/  || (0,0));
$main::build += $VERSION;
$main::branch += $BRANCH;

@ISA = qw{DXSql};

1;  
