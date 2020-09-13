#
# WSJTX logging and control protocol decoder etc
#
#

package WSJTX;

use strict;
use warnings;
use 5.22.1;

use JSON;

my $json;

sub handle
{
	my ($self, $handle, $data) = @_;

	my $lth = length $data;
	dbgdump('udp', "UDP IN lth: $lth", $data);

}

sub finish
{

}

sub per_sec
{

}

sub per_minute
{

}


1;
