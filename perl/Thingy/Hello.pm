#
# Hello Thingy handling
#
# $Id$
#
# Copyright (c) 2005 Dirk Koopman G1TLH
#

use strict;

package Thingy::Hello;

use vars qw($VERSION $BRANCH);
$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /\d+\.\d+\.(\d+)\.(\d+)/  || (0,0));
$main::build += $VERSION;
$main::branch += $BRANCH;

use DXChannel;
use DXDebug;
use Verify;
use Thingy;

use vars qw(@ISA);
@ISA = qw(Thingy);

sub gen_Aranea
{
	my $thing = shift;
	unless ($thing->{Aranea}) {
		my $auth = $thing->{auth} = Verify->new($main::mycall, $main::systime);
		$thing->{Aranea} = Aranea::genmsg($thing, 'HELLO', sw=>'DXSpider',
										  v=>$main::version,
										  b=>$main::build,
										  auth=>$auth->challenge($main::me->user->passphrase)
									  );
	}
	return $thing->{Aranea};
}

sub from_Aranea
{
	my $line = shift;
	my $thing = Aranea::input($line);
	return unless $thing;
}
1;
