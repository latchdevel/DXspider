#
# WSJTX logging and control protocol decoder etc
#
#

package WSJTX;

use strict;
use warnings;
use 5.22.1;

use JSON;
use DXDebug;

my $json;

sub new
{
	return bless {}, 'WSJTX';
}

sub handle
{
	my ($self, $handle, $data) = @_;

	my $lth = length $data;
	dbgdump('udp', "UDP IN lth: $lth", $data);
	return 1;
	
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
