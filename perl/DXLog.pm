#
# the general purpose logging machine
#
# This module is designed to allow you to log stuff in specific places
# and will rotate logs on a monthly, weekly or daily basis. 
#
# The idea is that you give it a prefix which is a directory and then 
# the system will log stuff to a directory structure which looks like:-
#
# daily:-
#   spots/1998/<julian day no>[.<optional suffix>]
#
# weekly :-
#   log/1998/<week no>[.<optional suffix>]
#
# monthly
#   wwv/1998/<month>[.<optional suffix>]
#
# Routines are provided to read these files in and to append to them
# 
# Copyright (c) - 1998 Dirk Koopman G1TLH
#
# $Id$
#

package DXLog;

use FileHandle;
use DXVars;
use DXDebug;
use DXUtil;
use Julian;
use Carp;

use strict;
