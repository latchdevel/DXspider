package Thingy::RouteUser;

use vars qw($VERSION $BRANCH %valid);
$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /\d+\.\d+\.(\d+)\.(\d+)/  || (0,0));
$main::build += $VERSION;
$main::branch += $BRANCH;

%valid = (
		  list => '0,List of Calls,parray',
		  new => '0,List of new Routes,parray',
		 );

sub add
{
	my $self = shift;

	my $dxchan = DXChannel->get($self->{fromdxchan});
	my $parent = Route::Node::get($self->{fromnode});
	
	my @rout;
	foreach my $r (@{$self->{list}}) {

		my $user;
		if ($sort eq 'U') {
			my $old = Route::User::get($r->call);
			if ($old) {
				if ($old->flags != $r->flags) {
					$old->flags($r->flags);
					push @rout, $r;
				}
				$old->addparent($parent);
			} else {
				$r->register;
				$parent->add_user($r->call);
				$r->add_parent($parent);
				push @rout, $r;
			}
			
			# add this station to the user database, if required
			$call =~ s/-\d+$//o;        # remove ssid for users
			$user = DXUser->get_current($call) || DXUser->new($call);
			$user->homenode($parent->call) unless $user->homenode;
			$user->node($parent->call);
		} elsif ($sort eq 'N') {
			my $old = Route::Node::get($call);
			if ($old) {
				my $ar;
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
				if ($call eq $self->{call}) {
					dbg("DXPROT: my channel route for $call has disappeared");
					next;
				};
				
				my $new = Route->new($call);          # throw away
				if ($dxchan->in_filter_route($new)) {
					my $r = $parent->add($call, $ver, $flags);
					push @rout, $r;
				} else {
					next;
				}
			}

			# add this station to the user database, if required (don't remove SSID from nodes)
			my $user = DXUser->get_current($call);
			unless ($user) {
				$user = DXUser->new($call);
				$user->sort('A');
				$user->priv(1);                   # I have relented and defaulted nodes
				$user->lockout(1);
				$user->homenode($call);
				$user->node($call);
			}
		}
		$user->lastin($main::systime) unless DXChannel->get($call);
		$user->put;
	}
	$self->{new} = \@rout;
}
