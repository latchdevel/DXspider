#!/bin/sh
#
# fix the stupid y2k bug in 1.37, just run this once
# and all should be OK.
#
# BEFORE running this script, kill off and otherwise prevent any 
# cluster.pl scripts from running.
#
# This means that if you are running cluster.pl from /etc/inittab or using
# some other means of dealing with automatically restarting cluster.pl - 
# MAKE SURE that you disable them.
#
# PLEASE make sure that no cluster.pl process is running whilst
# this shell script is running
#
cd /spider/data
mv wwv/100 wwv/2000
mv spots/100 spots/2000
mv debug/100 debug/2000
mv log/100 log/2000
