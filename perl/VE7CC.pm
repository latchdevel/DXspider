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
use DXUser;

use strict;

use vars qw($VERSION $BRANCH);
$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /\d+\.\d+\.(\d+)\.(\d+)/  || (0,0));
$main::build += $VERSION;
$main::branch += $BRANCH;

sub dx_spot
{
	my $self = shift;			# this may be useful some day
	my $spot = ref $_[0] ? shift : \@_;
	my $freq = $spot->[0];
	my $spotted = $spot->[1];
	my $t = $spot->[2];
	my $loc_spotted = '';
	my $loc_spotter = '';
	my $ref = DXUser->get_current($spotted);
	if ($ref) {
		my $loc = $ref->qra || '';
		$loc_spotted =substr($loc, 0, 4) if $loc;
	}

	# remove any items above the top of the max spot data
	pop while @_ > 14;
	
	# make sure both US states are defined
	$_[12] ||= '';
	$_[13] ||= '';
	
	my $spotted_cc = (Prefix::cty_data($spotted))[5];
	my $spotter_cc = (Prefix::cty_data($_[4]))[5];
	$ref = DXUser->get_current($_[4]);
	if ($ref) {
		my $loc = $ref->qra || '';
		$loc_spotter = substr($loc, 0, 4) if $loc;
	}
	
	return sprintf("CC11^%0.1f^%s^", $freq, $spotted) . join('^', cldate($t), ztime($t), @$spot[3..-1], $spotted_cc, $spotter_cc, $loc_spotted, $loc_spotter);
}

1;
