#
# Copy this file to /spider/local and modify it to your requirements
#
#
# This file specifies whether you want to connect to a BPQ32 Switch
# You are only likely to want to do this in a Microsoft Windows
# environment
#

package BPQMsg;

use strict;
use vars qw($enable $ApplMask $BPQStreams);

# set this to 1 to enable BPQ handling

$enable = 0;

# Applmask is normally 1, unless you are already running another BPQ app such as a BBS

$ApplMask = 1;

# Streams to allocate - used both for incomming and outgoing connects

$BPQStreams = 10;

1;
