#
# XML handler
#
# $Id$
#
# Copyright (c) Dirk Koopman, G1TLH
#

use strict;

package DXXml;

use DXChannel;
use DXProt;

use vars qw($VERSION $BRANCH $xs);
$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /\d+\.\d+\.(\d+)\.(\d+)/  || (0,0));
$main::build += $VERSION;
$main::branch += $BRANCH;

$xs = undef;							# the XML::Simple parser instance

sub init
{
	return unless $main::do_xml;
	
	eval { require XML::Simple; };
	unless ($@) {
		import XML::Simple;
		$DXProt::handle_xml = 1;
		$xs = new XML::Simple();
	}
	undef $@;
}

sub normal
{

}

sub process
{

}
1;
