#
# show/rbn [all|<call>,,,]
# 
# This command either lists all rbn users known about (sh/rbn all)
# or the ones specified on the command line, If no arguments are present
# then it will list all connected rbn/skimmer users.
#
# Copyright (c) 2020 Dirk Koopman G1TLH
#


my ($self, $line) = @_;
return (1, $self->msg('e5')) unless $self->priv >= 1;

my @call = map {uc $_} split /\s+/, $line; 
my @out;
my $count;

# search thru the user
if (@call == 0) {
	@call = sort map{$_->call} grep {$_->user->call && $_->user->wantrbn} DXChannel::get_all_users();
} elsif ($call[0] eq 'ALL') {
	shift @call;
	my ($action, $key, $data) = (0,0,0);
	for ($action = DXUser::R_FIRST, $count = 0; !$DXUser::dbm->seq($key, $data, $action); $action = DXUser::R_NEXT) {
		if (is_callsign($key)) {
			if ($data =~ /"sort":"[UW]"/  && $data =~ /"wantrbn":1/) {
				push @call, $key;
			}
		}
	}
}

push @out, join(' ', $self->msg('rbnusers'), $main::mycall);
my @l;

foreach my $call (@call) {
	push @l, $call;
	if (@l >= 5) {
		push @out, sprintf "%-12s %-12s %-12s %-12s %-12s", @l;
		@l = ();
	}
	++$count;
}
if (@l) {
	push @l, "" while @l < 5;
	push @out, sprintf "%-12s %-12s %-12s %-12s %-12s", @l;
}
	

return (1, @out, $self->msg('rec', $count));




