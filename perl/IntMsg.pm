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
	my $msg;
	
	while ($msg = shift @{$conn->{inqueue}}){
		$msg =~ s/\%([2-9A-F][0-9A-F])/chr(hex($1))/eg;
		$msg =~ s/[\x00-\x08\x0a-\x1f\x80-\x9f]/./g;         # immutable CSI sequence + control characters
		&{$conn->{rproc}}($conn, $msg, $!);
		$! = 0;
	}
}
