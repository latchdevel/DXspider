#!/usr/bin/perl
#
# a little program to see if I can use ax25_call in a perl script
#

use FileHandle;
use IPC::Open2;

$pid = Open2( \*IN, \*OUT, "ax25_call ether GB7DJK-1 G1TLH");

IN->input_record_separator("\r");
OUT->output_record_separator("\r");
OUT->autoflush(1);

vec($rin, fileno(STDIN), 1) = 1;
vec($rin, fileno(IN), 1) = 1;

while (($nfound = select($rout=$rin, undef, undef, 0.001)) >= 0) {
  
}
