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

sub dx_spot
{
	my $self = shift;			# this may be useful some day
	my $freq = shift;
	my $spotted = shift;
	my $t = shift;
	my $loc_spotted = '';
	my $loc_spotter = '';
	my $ref = DXUser::get_current($spotted);
	if ($ref) {
		my $loc = $ref->qra || '';
		$loc_spotted =substr($loc, 0, 4) if $loc;
	}

	# remove any items above the top of the max spot data
	pop while @_ > 11;
	
	# make sure both US states are defined
	$_[9] ||= '';
	$_[10] ||= '';
	
	my $spotted_cc = (Prefix::cty_data($spotted))[5];
	my $spotter_cc = (Prefix::cty_data($_[1]))[5];
	$ref = DXUser::get_current($_[1]);
	if ($ref) {
		my $loc = $ref->qra || '';
		$loc_spotter = substr($loc, 0, 4) if $loc;
	}
	my $text = $_[4];
	$text =~ s/\^/~/g;
	
	return sprintf("CC11^%0.1f^%s^", $freq, $spotted) . join('^', cldate($t), ztime($t), @_[0..3], $text, @_[5..10], $spotted_cc, $spotter_cc, $loc_spotted, $loc_spotter);
}

1;
