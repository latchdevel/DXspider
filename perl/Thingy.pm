#
# This module is the factory method for dealing with routable entities
# It will route transforming them on the way as required.
#
# Copyright (c) 2001 Dirk Koopman G1TLH
#
# $Id$
# 

package Thingy;

use strict;

use DXDebug;

use vars qw($VERSION $BRANCH);
$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /\d+\.\d+\.(\d+)\.(\d+)/  || (0,0));
$main::build += $VERSION;
$main::branch += $BRANCH;

use vars qw(%valid);

%valid = (
		  sort => '0,Sort',
		  tonode => '0,To Node',
		  fromnode => '0,From Node',
		  id => '0,Msg Id',
		  origin => '0,Origin Node',
		  line => '0,Input Line',
		 );


sub init
{

}

sub new
{
	my $pkg = shift;
	my $self = {@_};
	return bless $self, $pkg;
}

sub AUTOLOAD
{
	my ($pkg, $name) = $AUTOLOAD =~ /^(.*)::(\w+)$/;
	return if $name eq 'DESTROY';
  
	my $v = "${pkg}::valid";
	confess "Non-existant field '$AUTOLOAD'" unless $$v{$name} || $valid{$name};

	*$AUTOLOAD = sub {@_ > 1 ? $_[0]->{$name} = $_[1] : $_[0]->{$name}};
	goto &$AUTOLOAD;
}

1;

