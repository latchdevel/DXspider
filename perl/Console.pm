#
# These are the default variables for the console program
#
# DON'T ALTER this file, copy it to ../local and alter that
# instead. This file will be overwritten with new releases
#
# Copyright (c) 1999 Dirk Koopman G1TLH
#
# $Id$
#
# The colour pairs are:-
#
# 0 - $foreground, $background
# 1 - RED, $background
# 2 - BROWN, $background
# 3 - GREEN, $background
# 4 - CYAN, $background
# 5 - BLUE, $background
# 6 - MAGENTA, $background
#

package main;

$maxkhist = 100;
$maxshist = 500;
if ($ENV{'TERM'} =~ /xterm/) {
	$ENV{'TERM'} = 'color_xterm';
	$foreground = COLOR_BLACK();
	$background = A_BOLD|COLOR_WHITE();
}
if ($ENV{'TERM'} =~ /(console|linux)/) {
	$foreground = COLOR_WHITE();
	$background = COLOR_BLACK();
}

@colors = (
		   [ '^DX de [\-\w]+:\s+(14[45]\d\d\d|5[01]\d\d\d)', COLOR_PAIR(1) ],
		   [ '^DX', COLOR_PAIR(2) ],
		   [ '^To', COLOR_PAIR(3) ],
		   [ '^WWV', COLOR_PAIR(4) ],
		   [ '^WX', COLOR_PAIR(5) ],
);

1; 
