#
# Generate route Thingies
#
# $Id$
#
# Copyright (c) 2004 Dirk Koopman G1TLH
#

package Thingy::Route;

use strict;

use vars qw($VERSION $BRANCH);
$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /\d+\.\d+\.(\d+)\.(\d+)/  || (0,0));
$main::build += $VERSION;
$main::branch += $BRANCH;

use vars qw(@ISA);

@ISA = qw(Thingy);

# this is node connect 
sub new_node_connect
{
	my $pkg = shift;
	my $fromnode = shift;
	my $inon = shift;
	my $msgid = shift;
	my $t = $pkg->SUPER::new(_fromnode=>$fromnode, _msgid=>$msgid, 
							 _inon=>$inon,
							 t=>'nc', n=>join('|', @_));
	return $t;
}

# this is node disconnect 
sub new_node_disconnect
{
	my $pkg = shift;
	my $fromnode = shift;
	my $inon = shift;
	my $msgid = shift;
	my $t = $pkg->SUPER::new(_fromnode=>$fromnode, _msgid=>$msgid, 
							 _inon=>$inon,
							 t=>'nd', n=>join('|', @_));
	return $t;
}

# a full node update
sub new_node_update
{
	my $pkg = shift;
	my $msgid = shift;
	
	my @nodes = grep {$_ ne $main::mycall} DXChannel::get_all_node_calls();
	my @users = DXChannel::get_all_user_calls();
	
	my $t = $pkg->SUPER::new(_msgid=>$msgid, t=>'nu', 
							 id=>"DXSpider $main::version $main::build", 
							 n=>join('|', @nodes), u=>join('|', @users));
	return $t;
}

sub normal
{

}
