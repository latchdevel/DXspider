#
# show/lockout
#
# show all excluded users 
#
# Copyright (c) 2000 Dirk Koopman G1TLH
#
# $Id$
#

my ($self, $line) = @_;
return (1, $self->msg('e5')) unless $self->priv >= 9;

my @out;

use DB_File;

my ($action, $count, $key, $data);
for ($action = R_FIRST, $count = 0; !$DXUser::dbm->seq($key, $data, $action); $action = R_NEXT) {
	if ($data =~ m{lockout =>}) {
		my $u = DXUser->get_current($key);
		if ($u && $u->lockout) {
			push @out, $key;
			++$count;
		}
	}
} 

return (1, @out, $self->msg('rec', $count));


