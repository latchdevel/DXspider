#
# Ping Thingy handling
#
# $Id$
#
# Copyright (c) 2005 Dirk Koopman G1TLH
#

use strict;

package Thingy::Ping;

use vars qw($VERSION $BRANCH);

main::mkver($VERSION = q$Revision$);

use DXChannel;
use DXDebug;
use DXUtil;
use Thingy;
use Spot;
use Time::HiRes qw(gettimeofday tv_interval);


use vars qw(@ISA %ping $ping_ttl);
@ISA = qw(Thingy);

my $id;
$ping_ttl = 300;				# default ping ttl


sub gen_Aranea
{
	my $thing = shift;
	unless ($thing->{Aranea}) {
	 	$thing->{Aranea} = Aranea::genmsg($thing, qw(id out o));
	}
 	return $thing->{Aranea};
}

sub from_Aranea
{
	my $thing = shift;
	return unless $thing;
	return $thing;
}

sub gen_DXProt
{
	my $thing = shift;
	my $dxchan = shift;
	unless ($thing->{DXProt}) {
		# we need to tease out the nodes out of all of this.
		# bear in mind that a proxied PC prot node could be in
		# {user} as well as a true user and also it may not
		# have originated here.

		my $from = $thing->{o} if $thing->{out};
	    $from ||= $thing->{user} if Route::Node::get($thing->{user});
		$from ||= $thing->{origin};
		my $to = $thing->{o} unless $thing->{out};
		$to ||= $thing->{touser} if Route::Node::get($thing->{touser});
		$to ||= $thing->{group};

		
		$thing->{DXProt} = DXProt::pc51($to, $from, $thing->{out});
	}
	return $thing->{DXProt};
}

sub gen_DXCommandmode
{
	my $thing = shift;
	my $dxchan = shift;
	my $buf;
	if ($dxchan->{call} eq $thing->{touser}) {
		$buf = $dxchan->msg('pingi', ($thing->{user} || $thing->{origin}), $thing->{ft}, $thing->{fave});
	}
	return $buf;
}

# called with the dxchan, line and the split out arguments
sub from_DXProt
{
	my $thing = ref $_[0] ? shift : $_[0]->SUPER::new(origin=>$main::mycall);
	my $dxchan = shift;
	$thing->{DXProt} = shift;
	shift;						# PC51
	$thing->{group} = shift;	# to call
	my $from = shift;
	$thing->{out} = shift;		# 1 = ping, 0 = pong;
	$thing->{user} = $dxchan->{call};
	$thing->{o} = $from unless $from eq $dxchan->{call};
	$thing->remember if $thing->{out} && $thing->{group} ne $main::mycall;
	return $thing;
}

sub handle
{
	my $thing = shift;
	my $dxchan = shift;

	# is it for us?
	if ($thing->{group} eq $main::mycall) {
		if ($thing->{out} == 1) {
			my $repthing = $thing->new_reply;
			$repthing->{out} = 0;
			$repthing->{id} = $thing->{id};
			$repthing->{o} = $thing->{o} if $thing->{o};
			$repthing->send($dxchan) if $repthing;
		} else {

			# it's a reply, look in the ping list for this one
			my $ref = $ping{$thing->{id}} if exists $thing->{id};
			$ref ||= find(($thing->{user}||$thing->{origin}), ($thing->{touser}||$thing->{group}));
			if ($ref) {
				my $t = tv_interval($ref->{t}, [ gettimeofday ]);
				my $tochan = DXChannel::get($ref->{touser} || $ref->{group});
				if ($tochan) {
					my $nopings = $tochan->user->nopings || $DXProt::obscount;
					push @{$tochan->{pingtime}}, $t;
					shift @{$tochan->{pingtime}} if @{$tochan->{pingtime}} > 6;
					
					# cope with a missed ping, this means you must set the pingint large enough
					if ($t > $tochan->{pingint}  && $t < 2 * $tochan->{pingint} ) {
						$t -= $tochan->{pingint};
					}
					
					# calc smoothed RTT a la TCP
					if (@{$tochan->{pingtime}} == 1) {
						$tochan->{pingave} = $t;
					} else {
						$tochan->{pingave} = $tochan->{pingave} + (($t - $tochan->{pingave}) / 6);
					}
					$tochan->{nopings} = $nopings; # pump up the timer
				}
				if (my $dxc = DXChannel::get($ref->{user} || $ref->{origin})) {
					$thing->{ft} = sprintf "%.2f", $t;
					$thing->{fave} = sprintf "%.2f", $tochan ? ($tochan->{pingave} || $t) : $t;
					$thing->send($dxc);
				}
				delete $ping{$ref->{id}};
			}
		}
	} else {
		$thing->broadcast($dxchan);
	}
}

# this just creates a ping for onward transmission
# remember it if you want to ping someone from here	
sub new_ping
{
	my $pkg = shift;
	my $thing = $pkg->SUPER::new(@_);
}

# do this for pings we generate ourselves
sub remember
{
	my $thing = shift;
	$thing->{t} = [ gettimeofday ];
	$thing->{out} = 1;
	$thing->{id} = ++$id;
	my $u = DXUser->get_current($thing->{to});
	if ($u) {
		$u->lastping(($thing->{user} || $thing->{group}), $main::systime);
		$u->put;
	}
	$ping{$id} = $thing;
}

# remove any pings outstanding that we have remembered for this
# callsign, return the number of forgotten pings
sub forget
{
	my $call = shift;
	my $count = 0;
	my @out;	
	foreach my $thing (values %ping) {
		if (($thing->{user} || $thing->{group}) eq $call) {
			$count++;
			delete $ping{$thing->{id}};
		}
	}
	return $count;
}

sub find
{
	my $to = shift;
	my $from = shift;
	my $user = shift;
	
	foreach my $thing (values %ping) {
		if ($thing->{origin} eq $from && $thing->{group} eq $to) {
			if ($user) {
				return if $thing->{user} && $thing->{user} eq $user; 
			} else {
				return $thing;
			}
		}
	}
	return undef;
}
1;
