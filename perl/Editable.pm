#
# A module to allow a user to create and (eventually) edit arrays of
# text and attributes
#
# This is used for creating mail messages and user script files
#
# It may be sub-classed
#
# Copyright (c) 2001 Dirk Koopman G1TLH
#
# $Id$
#

package Editable;

use vars qw($VERSION $BRANCH);
$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /\d+\.\d+\.(\d+)\.(\d+)/ ) || 0;
$main::build += $VERSION;
$main::branch += $BRANCH;

sub new
{
	my $pkg = shift;
	my $class = ref $pkg || $pkg;
	
	return {}, $class; 
}

1;
