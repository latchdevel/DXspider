#
# Generate Hi (Hello) Thingies
#
# $Id$
#
# Copyright (c) 2004 Dirk Koopman G1TLH
#

package Thingy::Hi;

use strict;

use vars qw($VERSION $BRANCH);
$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /\d+\.\d+\.(\d+)\.(\d+)/,(0,0));
$main::build += $VERSION;
$main::branch += $BRANCH;

use vars qw(@ISA);

@ISA = qw(Thingy);

# this is my version of a PC18
sub new
{
	my $pkg = shift;
	my $tonode = shift;
	my $t = $pkg->SUPER::new( _tonode=>$tonode,
							 id=>'DXSpider', v=>$main::version, b=>$main::build);
	return $t;
}

sub normal
{
	my $t = shift;
	my $dxchan = DXChannel->get($t->{_fromnode});
	my $r = Route::Node::get($t->{_fromnode}) || Route::Node->new($t->{_fromnode});
	$r->version($t->{v});
	$r->build($t->{b});
	$r->software($t->{id});
	$r->np(1);
	$r->lid($t->{_msgid});
	$r->lastupdate($main::systime);

	if ($dxchan->state eq 'init') {
		my $ot = Thingy::Hi->new($t->{_fromnode});
		$dxchan->t_send($ot);
		$dxchan->state('normal');
	}
}

1;

