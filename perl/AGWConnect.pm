#
# Copy this file to /spider/local and modify it to your requirements
#
#
# This file specifies whether you want to connect to an AGW Engine 
# You are only likely to want to do this in a Microsoft Windows
# environment
#

package AGWMsg;

use strict;
use vars qw($enable $login $passwd $addr $port $monitor $ypolltime $hpolltime);

# set this to 1 to enable AGW Engine handling
$enable = 0;

# user name you are logging in as
$login = '';

# password required
$passwd = '';

#
# -- don't change these unless you know what you are doing --
#
# the ip address of the AGW engine you are connecting to
$addr = "localhost";

# the port number the AGW engine is listening to
$port = 8000;

# default monitor status
$monitor = 0;

# time between polls of channel queues
$ypolltime = 10;

# time between polls of Mheard
$hpolltime = 120;
 
1;
