# 
# the help subsystem
#
# It is a very simple system in that you type in 'help <cmd>' and it
# looks for a file called <cmd>.hlp in either the local_cmd directory
# or the cmd directory (in that order). 
#
# if you just type in 'help' by itself you get what is in 'help.hlp'.
#
# Copyright (c) 1998 - Dirk Koopman G1TLH
#
# $Id$
#

my ($self, $line) = @_;
my @out;



