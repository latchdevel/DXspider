#
# set the email address  of the user
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

return (1, $self->msg('emaile1')) if !$line;

$user = DXUser->get_current($call);
if ($user) {
	$user->email($line);
	$user->put();
	return (1, $self->msg('emaila', $line));
} else {
	return (1, $self->msg('namee2', $call));
}

