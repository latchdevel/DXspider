#
# The system variables - those indicated will need to be changed to suit your
# circumstances (and callsign)
#
# Copyright (c) 1998 - Dirk Koopman G1TLH
#
# $Id$
#

package main;

require Exporter;
@ISA = qw(Exporter);

@EXPORT_OK = qw($mycall $myname $myalias $mylatitude $mylongtitude $mylocator
                $myqth $myemail $myprot_version 
                $clusterport $clusteraddr $debugfn 
                $def_hopcount $root $data $system $cmd
				$userfn $motd $local_cmd $mybbsaddr
				$pc50_interval, $user_interval
               );
			   
			   
# this really does need to change for your system!!!!			   
$mycall = "GB7DJK";

# your name
$myname = "Dirk";

# Your 'normal' callsign 
$myalias = "G1TLH";

# Your latitude (+)ve = North (-)ve = South in degrees and decimal degrees
$mylatitude = +52.68584579;

# Your Longtitude (+)ve = East, (-)ve = West in degrees and decimal degrees
$mylongtitude = +0.94518260;

# Your locator (yes I know I can calculate it - eventually)
$mylocator = "JO02LQ";

# Your QTH (roughly)
$myqth = "East Dereham, Norfolk";

# Your e-mail address
$myemail = "djk\@tobit.co.uk";

# Your BBS addr
$mybbsaddr = "G1TLH\@GB7TLH.#35.GBR.EU";

# the tcp address of the cluster and so does this !!!
$clusteraddr = "dirk1.tobit.co.uk";

# the port number of the cluster (just leave this, unless it REALLY matters to you)
$clusterport = 27754;

# cluster debug file
$debugfn = "/tmp/debug_cluster";

# your favorite way to say 'Yes'
$yes = 'Yes';

# your favorite way to say 'No'
$no = 'No';

# the interval between unsolicited prompts if not traffic
$user_interval = 11*60;

# root of directory tree for this system
$root = "/spider"; 

# data files live in 
$data = "$root/data";

# system files live in
$system = "$root/sys";

# command files live in
$cmd = "$root/cmd";

# local command files live in (and overide $cmd)
$localcmd = "$root/local_cmd";

# where the user data lives
$userfn = "$data/users";

# the "message of the day" file
$motd = "$data/motd";

# are we debugging ?
@debug = ('chan');
