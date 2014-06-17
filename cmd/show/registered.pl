#
# show/registered
#
# show all registered users 
#
# Copyright (c) 2001 Dirk Koopman G1TLH
#
#
#

my ($self, $line) = @_;
return (1, $self->msg('e5')) unless $self->priv >= 9;

my @out;

use DB_File;

if ($line) {
	$line =~ s/[^\w\-\/]+//g;
	$line = "^\U\Q$line";
}

@out = $self->spawn_cmd(sub {
							my @out;
							my @val;
							

							my ($action, $count, $key, $data) = (0,0,0,0);
							eval qq{for (\$action = DXUser::R_FIRST, \$count = 0; !\$DXUser::dbm->seq(\$key, \$data, \$action); \$action = DXUser::R_NEXT) {
	if (\$data =~ m{registered}) {					
		if (!\$line || (\$line && \$key =~ /^$line/)) {
			my \$u = DXUser::get_current(\$key);
			if (\$u && \$u->registered) {
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
							push @out, , $self->msg('rec', $count);
							return @out;
						});

return (1, @out);


