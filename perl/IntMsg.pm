#
# This class is the internal subclass that deals with the internal port 27754
# communications for Msg.pm
#
# $Id$
#
# Copyright (c) 2001 - Dirk Koopman G1TLH
#

package IntMsg;

use strict;
use Msg;

use vars qw(@ISA);

@ISA = qw(Msg);

sub enqueue
{
	my ($conn, $msg) = @_;
	$msg =~ s/([\%\x00-\x1f\x7f-\xff])/sprintf("%%%02X", ord($1))/eg; 
    push (@{$conn->{outqueue}}, $msg . "\n");
}

sub dequeue
{
	my $conn = shift;

	if ($conn && $conn->{msg} =~ /\n/) {
		my @lines = split /\r?\n/, $conn->{msg};
		if ($conn->{msg} =~ /\n$/) {
			delete $conn->{msg};
		} else {
			$conn->{msg} = pop @lines;
		}
		for (@lines) {
			if (defined $_) {
				s/\%([0-9A-F][0-9A-F])/chr(hex($1))/eg;
				s/[\x00-\x08\x0a-\x19\x1b-\x1f\x80-\x9f]/./g;         # immutable CSI sequence + control characters
			} else {
				$_ = '';
			}
			&{$conn->{rproc}}($conn, $_) if exists $conn->{rproc};
		}
	}
}

