#
# Investigate whether an external node is accessible
#
# If it is, make it believable otherwise mark as not
# to be believed. 
#
# It is possible to store up state for a node to be 
# investigated, so that if it is accessible, its details
# will be passed on to whomsoever might be interested.
#
# Copyright (c) 2004 Dirk Koopman, G1TLH
#
# $Id$
#

use strict;

package Investigate;

use DXDebug;
use DXUtil;


use vars qw($VERSION $BRANCH);
$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /\d+\.\d+\.(\d+)\.(\d+)/  || (0,0));
$main::build += $VERSION;
$main::branch += $BRANCH;

use vars qw (%list %valid);

%list = ();						# the list of outstanding investigations
%valid = (						# valid fields
		  call => '0,Callsign',
		  start => '0,Started at,atime',
		  version => '0,Node Version',
		  build => '0,Node Build',
		  here => '0,Here?,yesno',
		  conf => '0,In Conf?,yesno',
		 );


sub new
{
	my $pkg = shift;
	my $call = shift;
	my $self = $list{$call} || bless { call=>$call, start=>$main::systime }, ref($pkg) || $pkg;
	return $self;
}

sub get
{
	return $list{$_[0]};
}

sub AUTOLOAD
{
	no strict;
	my $name = $AUTOLOAD;
	return if $name =~ /::DESTROY$/;
	$name =~ s/^.*:://o;
  
	confess "Non-existant field '$AUTOLOAD'" if !$valid{$name};

	# this clever line of code creates a subroutine which takes over from autoload
	# from OO Perl - Conway
	*$AUTOLOAD = sub {@_ > 1 ? $_[0]->{$name} = $_[1] : $_[0]->{$name}};
	goto &$AUTOLOAD;
}
1;
