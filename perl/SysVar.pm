# These are a load of system variables that used to live in DXVars.pm.
#
# They have been broken out into a separate module which must be called AFTER 'use DXVars' if that is in fact called at all.
#
# It is a replacement for DXVars.pm wherever it is used just for these paths
#

package main;

use vars qw($data $local_data $system $cmd $localcmd $userfn $motd);

##
## DXVars.pm overrides
##
# data files live in 
$data = "$root/data";

# for local data
$local_data = "$root/local_data";

# system files live in (except they don't, not really)
$system = "$root/sys";

# command files live in
$cmd = "$root/cmd";

# local command files live in (and overide $cmd)
$localcmd = "$root/local_cmd";

# where the user data lives
$userfn = "$local_data/users";

# the "message of the day" file
$motd = "motd";
