#
# VE7CC variations for DXCommandmode
#
# This is done this way because a) there aren't very many and 
# b) because it isn't easy to reliably rebless the object in
# flight (as it were).
#
# This could change.
#

package VE7CC;

use DXVars;
use DXDebug;
use DXUtil;
use Julian;
use Prefix;

use strict;

use vars qw($VERSION $BRANCH);
$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /\d+\.\d+\.(\d+)\.(\d+)/  || (0,0));
$main::build += $VERSION;
$main::branch += $BRANCH;

sub dx_spot
{
	my $self = shift;			# this may be useful some day
	my $freq = shift;
	my $spotted = shift;
	my $t = shift;
	
	# remove interface callsign;
	pop;
	
	my $spotted_cc = (Prefix::cty_data($spotted))[5];
	my $spotter_cc = (Prefix::cty_data($_[1]))[5];
	
	return sprintf("CC11^%0.1f^%s^", $freq, $spotted) . join('^', cldate($t), ztime($t), @_, $spotter_cc, $spotted_cc);
}

1;
