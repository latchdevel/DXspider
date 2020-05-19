#
# show/lockout
#
# show all excluded users 
#
# Copyright (c) 2000 Dirk Koopman G1TLH
#
#
#

sub handle
{
	my ($self, $line) = @_;
	return (1, $self->msg('e5')) unless $self->priv >= 9;

	my @out;

	if ($line) {
		$line =~ s/[^\w\-\/]+//g;
		$line = "\U\Q$line";
	}

	if ($self->{_nospawn}) {
		@out = generate($self, $line);
	} else {
		@out = $self->spawn_cmd("show/lockout $line", sub { return (generate($self, $line)); });
	}
	return (1, $self->msg('lockoutuse')) unless $line;
}


sub generate
{
	my $self = shift;
	my $line = shift;
	my @out;
	my @val;
	#	my ($action, $count, $key, $data) = (0,0,0,0);
	#	eval qq{for (\$action = DXUser::R_FIRST, \$count = 0; !\$DXUser::dbm->seq(\$key, \$data, \$action); \$action = DXUser::R_NEXT) {
	#	if (\$data =~ m{lockout}) {
	#		if (\$line eq 'ALL' || \$key =~ /^$line/) {
	#			my \$ur = DXUser::get_current(\$key);
	#			if (\$ur && \$ur->lockout) {
	#				push \@val, \$key;
	#				++\$count;
	#			}
	#		}
	#	}

#	$DB::single = 1;
	
	my @val;
	if ($line eq 'ALL') {
		@val = DXUser::scan(sub {
								my $k = shift;
								my $l = shift;
								# cheat, don't decode because we can easily pull it out from the json test
								return $l =~ m{"lockout":1} ? $k : ();
							});

	} else {
		for my $call (split /\s+/, $line) {
			my $l = DXUser::get($call, 1);
			next unless $l;
			next unless $l =~ m{"lockout":1};
			push @val, $call; 
		}
	}

	my $count = @val;
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
}



