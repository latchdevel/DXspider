#
# show/registered
#
# show all registered users 
#
# Copyright (c) 2001 Dirk Koopman G1TLH
#
# $Id$
#

my ($self, $line) = @_;
return (1, $self->msg('e5')) unless $self->priv >= 9;

my @out;

use DB_File;

if ($line) {
	$line =~ s/[^\w\-\/]+//g;
	$line = "^\U\Q$line";
}

my ($action, $count, $key, $data) = (0,0,0,0);
eval qq{for (\$action = DXUser::R_FIRST, \$count = 0; !\$DXUser::dbm->seq(\$key, \$data, \$action); \$action = DXUser::R_NEXT) {
	if (\$data =~ m{registered}) {					
		if (!\$line || (\$line && \$key =~ /^$line/)) {
			my \$u = DXUser->get_current(\$key);
			if (\$u && \$u->registered) {
				push \@out, \$key;
				++\$count;
			}
		}
	}
} };

push @out, $@ if $@;

return (1, @out, $self->msg('rec', $count));


