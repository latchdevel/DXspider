## Node routing routines## Copyright (c) 2001 Dirk Koopman G1TLH## $Id$#package Route::Node;use DXDebug;use Route;use Route::User;use DXUtil;use strict;use vars qw(%list %valid @ISA $max $filterdef $obscount);@ISA = qw(Route);%valid = (		  parent => '0,Parent Calls,parray',		  nodes => '0,Nodes,parray',		  users => '0,Users,parray',		  usercount => '0,User Count',		  version => '0,Version',		  handle_xml => '0,Using XML,yesno',		  lastmsg => '0,Last Route Msg,atime',		  lastid => '0,Last Route MsgID',		  do_pc9x => '0,Uses pc9x,yesno',		  via_pc92 => '0,Came in via pc92,yesno',		  obscount => '0,Obscount',);$filterdef = $Route::filterdef;%list = ();$max = 0;$obscount = 3;sub count{	my $n = scalar (keys %list);	$max = $n if $n > $max;	return $n;}sub max{	count();	return $max;}## this routine handles the possible adding of an entry in the routing# table. It will only add an entry if it is new. It may have all sorts of# other side effects which may include fixing up other links.## It will return a node object if (and only if) it is a completely new# object with that callsign. The upper layers are expected to do something# sensible with this!## called as $parent->add(call, dxchan, version, flags)#sub add{	my $parent = shift;	my $call = uc shift;	confess "Route::add trying to add $call to myself" if $call eq $parent->{call};	my $self = get($call);	if ($self) {		$self->_addparent($parent);		$parent->_addnode($self);		return undef;	}	$self = $parent->new($call, @_);	$parent->_addnode($self);	return $self;}## this routine is the opposite of 'add' above.## It will return an object if (and only if) this 'del' will remove# this object completely#sub del{	my $self = shift;	my $pref = shift;	# delete parent from this call's parent list	$pref->_delnode($self);    $self->_delparent($pref);	my @nodes;	my $ncall = $self->{call};	# is this the last connection, I have no parents anymore?	unless (@{$self->{parent}}) {		foreach my $rcall (@{$self->{nodes}}) {			next if grep $rcall eq $_, @_;			my $r = Route::Node::get($rcall);			push @nodes, $r->del($self, $ncall, @_) if $r;		}		$self->_del_users;		delete $list{$self->{call}};		push @nodes, $self;	}	return @nodes;}# this deletes this node completely by grabbing the parents# and deleting me from themsub delete{	my $self = shift;	my @out;	$self->_del_users;	foreach my $call (@{$self->{parent}}) {		my $parent = Route::Node::get($call);		push @out, $parent->del($self) if $parent;	}	return @out;}sub del_nodes{	my $parent = shift;	my @out;	foreach my $rcall (@{$parent->{nodes}}) {		my $r = get($rcall);		push @out, $r->del($parent, $parent->{call}, @_) if $r;	}	return @out;}sub _del_users{	my $self = shift;	for (@{$self->{users}}) {		my $ref = Route::User::get($_);		$ref->del($self) if $ref;	}	$self->{users} = [];}# add a user to this nodesub add_user{	my $self = shift;	my $ucall = shift;	confess "Trying to add NULL User call to routing tables" unless $ucall;	my $uref = Route::User::get($ucall);	my @out;	if ($uref) {		@out = $uref->addparent($self);	} else {		$uref = Route::User->new($ucall, $self->{call}, @_);		@out = $uref;	}	$self->_adduser($uref);	$self->{usercount} = scalar @{$self->{users}};	return @out;}# delete a user from this nodesub del_user{	my $self = shift;	my $ref = shift;	my @out;	if ($ref) {		@out = $self->_deluser($ref);		$ref->del($self);	} else {		confess "tried to delete non-existant $ref->{call} from $self->{call}";	}	$self->{usercount} = scalar @{$self->{users}};	return @out;}sub usercount{	my $self = shift;	if (@_ && @{$self->{users}} == 0) {		$self->{usercount} = shift;	}	return $self->{usercount};}sub users{	my $self = shift;	return @{$self->{users}};}sub nodes{	my $self = shift;	return @{$self->{nodes}};}sub parents{	my $self = shift;	return @{$self->{parent}};}sub rnodes{	my $self = shift;	my @out;	foreach my $call (@{$self->{nodes}}) {		next if grep $call eq $_, @_;		push @out, $call;		my $r = get($call);		push @out, $r->rnodes($call, @_) if $r;	}	return @out;}# this takes in a list of node and user calls (not references) from# a config type update for a node and returns# the differences as lists of things that have gone away# and things that have been added.sub calc_config_changes{	my $self = shift;	my %nodes = map {$_ => 1} @{$self->{nodes}};	my %users = map {$_ => 1} @{$self->{users}};	my $cnodes = shift;	my $cusers = shift;	if (isdbg('route')) {		dbg("ROUTE: start calc_config_changes");		dbg("ROUTE: incoming nodes on $self->{call}: " . join(',', sort @$cnodes));		dbg("ROUTE: incoming users on $self->{call}: " . join(',', sort @$cusers));		dbg("ROUTE: existing nodes on $self->{call}: " . join(',', sort keys %nodes));		dbg("ROUTE: existing users on $self->{call}: " . join(',', sort keys %users));	}	my (@dnodes, @dusers, @nnodes, @nusers);	push @nnodes, map {my @r = $nodes{$_} ? () : $_; delete $nodes{$_}; @r} @$cnodes;	push @dnodes, keys %nodes;	push @nusers, map {my @r = $users{$_} ? () : $_; delete $users{$_}; @r} @$cusers;	push @dusers, keys %users;	if (isdbg('route')) {		dbg("ROUTE: deleted nodes on $self->{call}: " . join(',', sort @dnodes));		dbg("ROUTE: deleted users on $self->{call}: " . join(',', sort @dusers));		dbg("ROUTE: added nodes on $self->{call}: " . join(',', sort  @nnodes));		dbg("ROUTE: added users on $self->{call}: " . join(',', sort @nusers));		dbg("ROUTE: end calc_config_changes");	}	return (\@dnodes, \@dusers, \@nnodes, \@nusers);}sub new{	my $pkg = shift;	my $call = uc shift;	confess "already have $call in $pkg" if $list{$call};	my $self = $pkg->SUPER::new($call);	$self->{parent} = ref $pkg ? [ $pkg->{call} ] : [ ];	$self->{version} = shift || 5401;	$self->{flags} = shift || Route::here(1);	$self->{users} = [];	$self->{nodes} = [];	$self->{lastid} = {};	$self->reset_obs;			# by definition	$list{$call} = $self;	return $self;}sub get{	my $call = shift;	$call = shift if ref $call;	my $ref = $list{uc $call};	dbg("Failed to get Node $call" ) if !$ref && isdbg('routerr');	return $ref;}sub get_all{	return values %list;}sub _addparent{	my $self = shift;    return $self->_addlist('parent', @_);}sub _delparent{	my $self = shift;    return $self->_dellist('parent', @_);}sub _addnode{	my $self = shift;    return $self->_addlist('nodes', @_);}sub _delnode{	my $self = shift;    return $self->_dellist('nodes', @_);}sub _adduser{	my $self = shift;    return $self->_addlist('users', @_);}sub _deluser{	my $self = shift;    return $self->_dellist('users', @_);}sub dec_obs{	my $self = shift;	$self->{obscount}--;	return $self->{obscount};}sub reset_obs{	my $self = shift;	$self->{obscount} = $obscount;}sub DESTROY{	my $self = shift;	my $pkg = ref $self;	my $call = $self->{call} || "Unknown";	dbg("destroying $pkg with $call") if isdbg('routelow');}## generic AUTOLOAD for accessors#sub AUTOLOAD{	no strict;	my $name = $AUTOLOAD;	return if $name =~ /::DESTROY$/;	$name =~ s/^.*:://o;	confess "Non-existant field '$AUTOLOAD'" unless $valid{$name} || $Route::valid{$name};	# this clever line of code creates a subroutine which takes over from autoload	# from OO Perl - Conway        *$AUTOLOAD = sub {$_[0]->{$name} = $_[1] if @_ > 1; return $_[0]->{$name}};        goto &$AUTOLOAD;}1;