#
# Generate route Thingies
#
# $Id$
#
# Copyright (c) 2004 Dirk Koopman G1TLH
#

package Thingy::Route;

use strict;

use vars qw($VERSION $BRANCH);
$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /\d+\.\d+\.(\d+)\.(\d+)/,(0,0));
$main::build += $VERSION;
$main::branch += $BRANCH;

use vars qw(@ISA);

@ISA = qw(Thingy);

# this is node connect 
sub new_node_connect
{
	my $pkg = shift;
	my $fromnode = shift;
	my $inon = shift;
	my @n = map {uc} @_;
	my $t = $pkg->SUPER::new(_fromnode=>$fromnode,
							 _inon=>$inon,
							 id=>'DXSpider', v=>$main::version, b=>$main::build, 							 t=>'nc', n=>\@n);
	return $t;
}

# this is node disconnect 
sub new_node_disconnect
{
	my $pkg = shift;
	my $fromnode = shift;
	my $inon = shift;
	my @n = map {uc} @_;
	my $t = $pkg->SUPER::new(_fromnode=>$fromnode,
							 _inon=>$inon,
							 t=>'nd', n=>\@n);
	return $t;
}

# a full node update
sub new_node_update
{
	my $pkg = shift;
	
	my @nodes = grep {$_ ne $main::mycall} DXChannel::get_all_node_calls();
	my @users = DXChannel::get_all_user_calls();
	
	my $t = $pkg->SUPER::new(t=>'nu', 
							 id=>'DXSpider', v=>$main::version, b=>$main::build, 
							 n=>\@nodes, u=>\@users);
	return $t;
}

sub new_user_connect
{
	my $pkg = shift;
	my $fromnode = shift;
	my $inon = shift;
	my @u = map {uc} @_;
	my $t = $pkg->SUPER::new(_fromnode=>$fromnode,
							 _inon=>$inon,
							 t=>'uc', u=>\@u);
	return $t;
}

sub new_user_discconnect
{
	my $pkg = shift;
	my $fromnode = shift;
	my $inon = shift;
	my @u = map {uc} @_;
	my $t = $pkg->SUPER::new(_fromnode=>$fromnode,
							 _inon=>$inon,
							 t=>'ud', u=>\@u);
	return $t;
}

sub normal
{

}

# node update (this will completely rewrite the node's info)
sub handle_nu
{
	my $t = shift;
	
}

# node connection
sub handle_nc
{
	my $t = shift;

	my @rout;
	
	# first get the fromnode
	my $dxchan = DXChannel->get($t->{_inon}) || return;
	my $parent = Route::Node::get($t->{_fromnode});

	unless ($parent) {
		push @rout, $parent = Route::Node->new($t->{_fromnode});
	}

	for (@{$t->{n}) {
		my ($here, $call) = unpack "AA*", $_;

		# if it is a new node add it to the user database
		my $user = DXUser->get_current($call);
		unless ($user) {
			$user = DXUser->new($call);
			$user->sort('A');
			$user->priv(1);		# I have relented and defaulted nodes
			$user->lockout(1);
			$user->homenode($call);
			$user->node($call);
		}

		# add each of the nodes to this parent
		
	}
		# add this station to the user database, if required (don't remove SSID from nodes)

		my $r = Route::Node::get($call);
		my $flags = Route::here($here)|Route::conf($conf);

		# modify the routing table if it is in it, otherwise store it in the pc19list for now
		if ($r) {
			my $ar;
			if ($call ne $parent->call) {
				if ($self->in_filter_route($r)) {
					$ar = $parent->add($call, $ver, $flags);
					push @rout, $ar if $ar;
				} else {
					next;
				}
			}
			if ($r->version ne $ver || $r->flags != $flags) {
				$r->version($ver);
				$r->flags($flags);
				push @rout, $r unless $ar;
			}
		} else {

			# if he is directly connected or allowed then add him, otherwise store him up for later
			if ($call eq $self->{call} || $user->wantroutepc19) {
				my $new = Route->new($call); # throw away
				if ($self->in_filter_route($new)) {
					my $ar = $parent->add($call, $ver, $flags);
					$user->wantroutepc19(1) unless defined $user->wantroutepc19;
					push @rout, $ar if $ar;
				} else {
					next;
				}
			} else {
				$pc19list{$call} = [] unless exists $pc19list{$call};
				my $nl = $pc19list{$call};
				push @{$pc19list{$call}}, [$self->{call}, $ver, $flags] unless grep $_->[0] eq $self->{call}, @$nl;
			}
		}

		# unbusy and stop and outgoing mail (ie if somehow we receive another PC19 without a disconnect)
		my $mref = DXMsg::get_busy($call);
		$mref->stop_msg($call) if $mref;
				
		$user->lastin($main::systime) unless DXChannel->get($call);
		$user->put;
	}


	$self->route_pc19($origin, $line, @rout) if @rout;
	
}

# node disconnection
sub handle_nd
{
	my $t = shift;
	
}

# user connection
sub handle_uc
{
	my $t = shift;

	my $newline = "PC16^";
	my $parent = Route::Node::get($t->{_fromnode}); 

	# if there is a parent, proceed, otherwise if there is a latent PC19 in the PC19list, 
	# fix it up in the routing tables and issue it forth before the PC16
	unless ($parent) {
		my $nl = $pc19list{$ncall};

		if ($nl && @_ > 3) { # 3 because of the hop count!

			# this is a new (remembered) node, now attach it to me if it isn't in filtered
			# and we haven't disallowed it
			my $user = DXUser->get_current($ncall);
			if (!$user) {
				$user = DXUser->new($ncall);
				$user->sort('A');
				$user->priv(1);	# I have relented and defaulted nodes
				$user->lockout(1);
				$user->homenode($ncall);
				$user->node($ncall);
			}

			my $wantpc19 = $user->wantroutepc19;
			if ($wantpc19 || !defined $wantpc19) {
				my $new = Route->new($ncall); # throw away
				if ($self->in_filter_route($new)) {
					my @nrout;
					for (@$nl) {
						$parent = Route::Node::get($_->[0]);
						$dxchan = $parent->dxchan if $parent;
						if ($dxchan && $dxchan ne $self) {
							dbg("PCPROT: PC19 from $self->{call} trying to alter locally connected $ncall, ignored!") if isdbg('chanerr');
							$parent = undef;
						}
						if ($parent) {
							my $r = $parent->add($ncall, $_->[1], $_->[2]);
							push @nrout, $r unless @nrout;
						}
					}
					$user->wantroutepc19(1) unless defined $wantpc19; # for now we work on the basis that pc16 = real route 
					$user->lastin($main::systime) unless DXChannel->get($ncall);
					$user->put;
						
					# route the pc19 - this will cause 'stuttering PC19s' for a while
					$self->route_pc19($origin, $line, @nrout) if @nrout ;
					$parent = Route::Node::get($ncall);
					unless ($parent) {
						dbg("PCPROT: lost $ncall after sending PC19 for it?");
						return;
					}
				} else {
					return;
				}
				delete $pc19list{$ncall};
			}
		} else {
			dbg("PCPROT: Node $ncall not in config") if isdbg('chanerr');
			return;
		}
	} else {
				
		$dxchan = $parent->dxchan;
		if ($dxchan && $dxchan ne $self) {
			dbg("PCPROT: PC16 from $self->{call} trying to alter locally connected $ncall, ignored!") if isdbg('chanerr');
			return;
		}

		# input filter if required
		return unless $self->in_filter_route($parent);
	}

	my $i;
	my @rout;
	for ($i = 2; $i < $#_; $i++) {
		my ($call, $conf, $here) = $_[$i] =~ /^(\S+) (\S) (\d)/o;
		next unless $call && $conf && defined $here && is_callsign($call);
		next if $call eq $main::mycall;

		eph_del_regex("^PC17\\^$call\\^$ncall");
				
		$conf = $conf eq '*';

		# reject this if we think it is a node already
		my $r = Route::Node::get($call);
		my $u = DXUser->get_current($call) unless $r;
		if ($r || ($u && $u->is_node)) {
			dbg("PCPROT: $call is a node") if isdbg('chanerr');
			next;
		}
				
		$r = Route::User::get($call);
		my $flags = Route::here($here)|Route::conf($conf);
				
		if ($r) {
			my $au = $r->addparent($parent);					
			if ($r->flags != $flags) {
				$r->flags($flags);
				$au = $r;
			}
			push @rout, $r if $au;
		} else {
			push @rout, $parent->add_user($call, $flags);
		}
		
				
		# add this station to the user database, if required
		$call =~ s/-\d+$//o;	# remove ssid for users
		my $user = DXUser->get_current($call);
		$user = DXUser->new($call) if !$user;
		$user->homenode($parent->call) if !$user->homenode;
		$user->node($parent->call);
		$user->lastin($main::systime) unless DXChannel->get($call);
		$user->put;
	}
	$self->route_pc16($origin, $line, $parent, @rout) if @rout;	
}

# user disconnection
sub handle_ud
{
	my $t = shift;

	my $uref = Route::User::get($ucall);
	unless ($uref) {
		dbg("PCPROT: Route::User $ucall not in config") if isdbg('chanerr');
		return;
	}
	my $parent = Route::Node::get($ncall);
	unless ($parent) {
		dbg("PCPROT: Route::Node $ncall not in config") if isdbg('chanerr');
		return;
	}			

	$dxchan = $parent->dxchan;
	if ($dxchan && $dxchan ne $self) {
		dbg("PCPROT: PC17 from $self->{call} trying to alter locally connected $ncall, ignored!") if isdbg('chanerr');
		return;
	}

	# input filter if required
	return unless $self->in_filter_route($parent);
			
	$parent->del_user($uref);

	if (eph_dup($line)) {
		dbg("PCPROT: dup PC17 detected") if isdbg('chanerr');
		return;
	}

	$self->route_pc17($origin, $line, $parent, $uref);
	
}
