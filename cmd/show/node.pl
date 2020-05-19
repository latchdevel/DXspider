#
# show/node [<node> | <node> ] 
# 
# This command either lists all nodes known about 
# or the ones specified on the command line together
# with some information that is relavent to them 
#
# This command isn't and never will be compatible with AK1A
#
# A special millenium treat just for G4PDQ
#
# Copyright (c) 2000-2020 Dirk Koopman G1TLH
#
#
#

sub handle
{
	my ($self, $line) = @_;
	return (1, $self->msg('e5')) unless $self->priv >= 1;
	my @out;
	
	my @call = map {uc $_} split /\s+/, $line;
	if ($self->{_nospawn}) {
		@out = generate($self, @call);
	} else {
		@out = $self->spawn_cmd("show/nodes $line", sub { return (generate($self, @call)); });
	}
	return (1, @out);
}

sub generate
{
	my $self = shift;
	my @call = @_;
	my @out;
	my $count;

	# search thru the user for nodes
	if (@call == 0) {
		@call = map {$_->call} DXChannel::get_all_nodes();
	}
	elsif ($call[0] eq 'ALL') {
		shift @call;
		#	my ($action, $key, $data) = (0,0,0);
		#	for ($action = DXUser::R_FIRST, $count = 0; !$DXUser::dbm->seq($key, $data, $action); $action = DXUser::R_NEXT) {
		#		if ($data =~ m{\01[ACRSX]\0\0\0\04sort}) {
		#		    push @call, $key;
		#			++$count;
		#		}
		#	}
	
		push @call, DXUser::scan(sub {
									  my $k = shift;
									  # cheat, don't decode because we can easily pull it out from the json test
									  return $_[0] =~ m{"sort":"[ACRSX]"} ? $k : ();
								  });
	}

	my $call;
	foreach $call (sort @call) {
		my $clref = Route::Node::get($call);
		my $l = DXUser::get($call, 1);
		next unless $l;
		my $uref = DXUser::json_decode($l);
		next unless $uref;
		my ($sort, $ver, $build);
	
		my $pcall = sprintf "%-11s", $call;
		push @out, $self->msg('snode1') unless @out > 0;
		if ($uref) {
			$sort = "Spider" if $uref->is_spider || ($clref && $clref->do_pc9x);
			$sort = "Clx   " if $uref->is_clx;
			$sort = "User  " if $uref->is_user;
			$sort = "BBS   " if $uref->is_bbs;
			$sort = "DXNet " if $uref->is_dxnet;
			$sort = "ARClus" if $uref->is_arcluster;
			$sort = "AK1A  " if !$sort && $uref->is_ak1a;
			$sort = "Unknwn" unless $sort;
		} else {
			push @out, $self->msg('snode3', $call);
			next;
		}
		$ver = "";
		$build = "";
		if ($call eq $main::mycall) {
			$sort = "Spider";
			$ver = $main::version;
		} else {
			$ver = $clref->version if $clref && $clref->version;
			$ver = $uref->version if !$ver && $uref->version;
			$sort = "CCClus" if $ver >= 1000 && $ver < 4000 && $sort eq "Spider";
		}
	
		if ($uref->is_spider || ($clref && $clref->do_pc9x)) {
			$ver /= 100 if $ver > 5400;
			$ver -= 53 if $ver > 54;
			if ($clref && $clref->build) {
				$build = "build: " . $clref->build
			}
			elsif ($uref->build) {
				$build = "build: " . $uref->build;
			}
			push @out, $self->msg('snode2', $pcall, $sort, "$ver $build");
		} else {
			my ($major, $minor, $subs) = unpack("AAA*", $ver) if $ver;
			push @out, $self->msg('snode2', $pcall, $sort, $ver ? "$major\-$minor.$subs" : "      ");
		}
		++$count;
	}

	return (1, @out, $self->msg('rec', $count));
}




