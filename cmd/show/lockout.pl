#
# show/lockout
#
# show all excluded users 
#
# Copyright (c) 2000 Dirk Koopman G1TLH
#
#
#

my ($self, $line) = @_;
return (1, $self->msg('e5')) unless $self->priv >= 9;

my @out;

use DB_File;

if ($line) {
	$line =~ s/[^\w\-\/]+//g;
	$line = "\U\Q$line";
}

return (1, $self->msg('lockoutuse')) unless $line;

@out = $self->spawn_cmd("show lockout $line", sub {
							my @out;
							my @val;
							my ($action, $count, $key, $data) = (0,0,0,0);
							eval qq{for (\$action = DXUser::R_FIRST, \$count = 0; !\$DXUser::dbm->seq(\$key, \$data, \$action); \$action = DXUser::R_NEXT) {
	if (\$data =~ m{lockout}) {
		if (\$line eq 'ALL' || \$key =~ /^$line/) {
			my \$ur = DXUser::get_current(\$key);
			if (\$ur && \$ur->lockout) {
				push \@val, \$key;
				++\$count;
			}
		}
	}
} };

							my @l;
							foreach my $call (@val) {
								if (@l >= 5) {
									push @out, sprintf "%-12s %-12s %-12s %-12s %-12s", @l;
									@l = ();
								}
								push @l, $call;
							}
							if (@l) {
								push @l, "" while @l < 5;
								push @out, sprintf "%-12s %-12s %-12s %-12s %-12s", @l;
							}

							push @out, $@ if $@;
							push @out, $self->msg('rec', $count);
							return @out;
						});


return (1, @out);


