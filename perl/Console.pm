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
# You can or these with A_BOLD and or A_REVERSE for a different effect
#

package main;

$maxkhist = 100;
$maxshist = 500;
if ($ENV{'TERM'} =~ /(xterm|ansi)/) {
	$ENV{'TERM'} = 'color_xterm';
	$foreground = COLOR_BLACK();
	$background = COLOR_WHITE();
	@colors = (
		   [ '^DX de [\-A-Z0-9]+:\s+(14[45]\d\d\d|5[01]\d\d\d)', COLOR_PAIR(1) ],
		   [ '^DX', COLOR_PAIR(5) ],
		   [ '^To', COLOR_PAIR(3) ],
		   [ '^WWV', COLOR_PAIR(4) ],
		   [ '^[-A-Z0-9]+ de [-A-Z0-9]+ \d\d-\w\w\w-\d\d\d\d \d\d\d\dZ', COLOR_PAIR(0) ],
		   [ '^[-A-Z0-9]+ de [-A-Z0-9]+ ', COLOR_PAIR(6) ],
		   [ '^WX', COLOR_PAIR(3) ],
		   [ '^New mail', A_BOLD|COLOR_PAIR(5) ],
		   );
}
if ($ENV{'TERM'} =~ /(console|linux)/) {
	$foreground = COLOR_WHITE();
	$background = COLOR_BLACK();
	@colors = (
		   [ '^DX de [\-\w]+:\s+(14[45]\d\d\d|5[01]\d\d\d)', COLOR_PAIR(1) ],
		   [ '^DX', COLOR_PAIR(4) ],
		   [ '^To', COLOR_PAIR(3) ],
		   [ '^WWV', COLOR_PAIR(5) ],
		   [ '^[-A-Z0-9]+ de [-A-Z0-9]+ \d\d-\w\w\w-\d\d\d\d \d\d\d\dZ', COLOR_PAIR(0) ],
		   [ '^[-A-Z0-9]+ de [-A-Z0-9]+ ', COLOR_PAIR(6) ],
		   [ '^WX', COLOR_PAIR(3) ],
		   [ '^New mail', A_BOLD|COLOR_PAIR(5) ],
		   );
}


1; 
