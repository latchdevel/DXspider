#
#
# These are various values used by the AK1A protocol stack
#
# Change these at your peril (or if you know what you are doing)!
#
# Copyright (c) 1998 - Dirk Koopman G1TLH
#
# $Id$
#

package DXProt;

# maximum number of users in a PC16 message
$pc16_max_users = 5;

# maximum number of nodes in a PC19 message
$pc19_max_nodes = 5;

# the interval between pc50s (in seconds)
$pc50_interval = 14*60;

# the version of DX cluster (tm) software I am masquerading as
$myprot_version = "5447";

# default hopcount to use
$def_hopcount = 15;

# some variable hop counts based on message type
%hopcount = (
  11 => 25,
  16 => 10,
  17 => 10,
  19 => 10,
  21 => 10,
);


