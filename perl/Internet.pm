# 
# in order for you to use the internet accessing routines you
# need to set various flags and things in this file
#
# BUT DO NOT ALTER THIS FILE! It will be overwritten on every update
#
# COPY this file to ../local, alter it there and restart the software
#
# Copyright (c) 2000 Dirk Koopman G1TLH
#
# $Id$
#

package Internet;

#
# set this flag to 1 if you want to allow internet commands
#

$allow = 0;

#
# QRZ.com user id 
#
# set this to your QRZ user name (you need this for the sh/qrz 
# command)
#
# eg 
# $qrz_uid = 'gb7xxx';
#


$qrz_uid = undef;

#
# QRZ.com password - this goes with your user id above
#
# eg 
# $qrz_pw = 'fishhooks';
#

$qrz_pw = undef;

#
# the address of any HTTP proxy you might be using
#
# leave as is unless you need one
#
# eg:  $http_proxy = 'wwwcache.demon.co.uk';
#

$http_proxy = undef;

#
# HTTP proxy port - again leave alone unless you need this
#
# eg: $http_proxy_port = 8080;
#

$http_proxy_port = undef;

#
# list of urls and other things that are used in commands, here so that they
# can be changed if necessary.
#

$qrz_url = 'www.qrz.com';     # used by show/qrz
$wm7d_url = 'www.wm7d.net';   # used by show/wm7d
$db0sdx_url = 'www.qslinfo.de'; # used by show/db0sdx
$db0sdx_path = '/qslinfo';
$db0sdx_suffix = '.asmx';
$dx425_url = 'www.ariscandicci.it';		# used by show/425
$contest_host = 'www.sk3bg.se';         # used by show/contest
$contest_url = "http://$contest_host/contest/text";         # used by show/contest

#
# end
#

1;
