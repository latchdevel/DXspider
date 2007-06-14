#
# XML IM handler (Chat, Announces, Talk)
#
# $Id$
#
# Copyright (c) Dirk Koopman, G1TLH
#

use strict;

package DXXml::IM;

use DXDebug;
use DXProt;
use IsoTime;
use Investigate;
use Time::HiRes qw(gettimeofday tv_interval);

use vars qw(@ISA %pings);
@ISA = qw(DXXml);

#
# This is the general purpose IM sentence
#
# It is of the form: <chat [to=<user call>|<node call>|<chat group>] ...>the text</chat>
#
# This covers:
#
#     announce/full        (no to=)
#     announce/local       (to="$mycall")
#     announce/<node call> (to="<node call>")
#     chat <group>         (to="<group>")
#     talk <user call>     (to="<user call>")
# 

sub handle_input
{
	my $self = shift;
	my $dxchan = shift;
	
	if ($self->{to} eq $main::mycall) {

	} else {
		$self->route($dxchan);
	}
}

sub topcxx
{
	my $self = shift;
	unless (exists $self->{'-pcxx'}) {
		if (my $to = $self->{to}) {
			if (Route::Node::get($to)) {
				
			}
		}
		$self->{'-pcxx'} = DXProt::pc51($self->{to}, $self->{o}, $self->{s});
	}
	return $self->{'-pcxx'};
}

1;
