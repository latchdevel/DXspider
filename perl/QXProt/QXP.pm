#
# This module is part of the new protocal mode for a dx cluster
#
# This module handles ping requests
#
# Copyright (c) 2003 Dirk Koopman G1TLH
#
# $Id$
# 

package QXP;

use strict;

use vars qw(@ISA $VERSION $BRANCH);
@ISA = qw(QXProt);

$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /\d+\.\d+\.(\d+)\.(\d+)/  || (0,0));
$main::build += $VERSION;
$main::branch += $BRANCH;

sub handle
{
	my ($self, $to, $from, $msgid, $line) = @_;
	
	my @f = split /\^/, $line;

	# is it for us?
	if ($to eq $main::mycall) {
		if ($f[0] == 1) {
			$self->send(gen($self, $from, '0', $f[1], $f[2], $f[3]));
		} else {
			# it's a reply, look in the ping list for this one
			$self->handlepingreply($from);
		}
	} else {

		# route down an appropriate thingy
		$self->route($to, $line);
	}
}

sub gen
{
	my ($self, $to, $flag, $user, $secs, $usecs) = @_;
	my @out = ('P', $to, $flag);
	push @out, $user if defined $user;
	push @out, $secs if defined $secs;	
	push @out, $usecs if defined $usecs;	
	return $self->frame(@out);
}

1;
