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

if ($line) {
	$line =~ s/[^\w-\/]+//g;
	$line = "^\U\Q$line";
}

my ($action, $count, $key, $data) = (0,0,0,0);
for ($action = DXUser::R_FIRST, $count = 0; !$DXUser::dbm->seq($key, $data, $action); $action = DXUser::R_NEXT) {
	if ($data =~ m{lockout =>}) {
		if ($line && $key =~ /$line/) {
			my $u = DXUser->get_current($key);
			if ($u && $u->lockout) {
				push @out, $key;
				++$count;
			}
		}
	}
} 

return (1, @out, $self->msg('rec', $count));


