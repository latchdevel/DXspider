#
# show/isolate
#
# show all excluded users 
#
# Copyright (c) 2000 Dirk Koopman G1TLH
#
#
#

my ($self, $line) = @_;
return (1, $self->msg('e5')) unless $self->priv >= 1;

my @out;

use DB_File;

@out = $self->spawn_cmd("show/isolate $line", sub {
							my @out;
							my @val;
							
							my ($action, $count, $key, $data) = (0,0,0,0);

							for ($action = DXUser::R_FIRST, $count=0; !$DXUser::dbm->seq($key, $data, $action); $action = DXUser::R_NEXT) {
								if ($data =~ m{isolate}) {
									my $u = DXUser::get_current($key);
									if ($u && $u->isolate) {
										push @val, $key;
										++$count;
									}
								}
							} 

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

							push @out, , $self->msg('rec', $count);
							return @out;
						});


return (1, @out);


