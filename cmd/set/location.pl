#
# set the latitude and longtitude field
#
# Copyright (c) 1998 - Dirk Koopman
#
# $Id$
#

my ($self, $line) = @_;
my $call = $self->call;
my $user;

# remove leading and trailing spaces
$line =~ s/^\s+//;
$line =~ s/\s+$//;

return (1, $self->msg('loce1')) if !$line;
return (1, $self->msg('loce2', $line)) unless $line =~ /\d+ \d+ [NnSs] \d+ \d+ [EeWw]/o;

$user = DXUser->get_current($call);
if ($user) {
	$line = uc $line;
	$user->qra($line);
	my ($lat, $long) = DXBearing::stoll($line);
	$user->lat($lat);
	$user->long($long);
	DXProt::broadcast_ak1a(DXProt::pc41($call, 3, $line), $DXProt::me);
	if (!$user->qra) {
		my $qra = DXBearing::lltos($lat, $long);
		$user->qra($qra);
	}
	
	$user->put();
	return (1, $self->msg('loc', $line));
} else {
	return (1, $self->msg('namee2', $call));
}
