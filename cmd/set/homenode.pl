#
# set the user's home node
#
# Copyright (c) 1998 - Dirk Koopman G1TLH
#
# $Id$
#

my ($self, $line) = @_;
my $call = $self->call;
my $user;

# remove leading and trailing spaces
$line =~ s/^\s+//;
$line =~ s/\s+$//;

return (1, $self->msg('hnodee1')) if !$line;

$user = DXUser->get_current($call);
if ($user) {
	$line = uc $line;
	$user->homenode($line);
	$user->put();
	DXProt::broadcast_all_ak1a(DXProt::pc41($call, 4, $line), $DXProt::me);
	return (1, $self->msg('hnode', $line));
} else {
	return (1, $self->msg('namee2', $call));
}

