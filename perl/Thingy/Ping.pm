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


use vars qw(@ISA %ping);
@ISA = qw(Thingy);

my $id;

sub gen_Aranea
{
	my $thing = shift;
	unless ($thing->{Aranea}) {
	 	$thing->{Aranea} = Aranea::genmsg($thing, qw(id out));
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

		my $from = $thing->{user} if Route::Node::get($thing->{user});
		$from ||= $thing->{origin};
		my $to = $thing->{touser} if Route::Node::get($thing->{touser});
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

	return $buf;
}

sub from_DXProt
{
	my $thing = ref $_[0] ? shift : $_[0]->SUPER::new();
	
	while (@_) {
		my $k = shift;
		$thing->{$k} = shift;
	}
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
			$repthing->send($dxchan) if $repthing;
		} else {

			# it's a reply, look in the ping list for this one
			my $ref = $ping{$thing->{id}} if $thing->{id}
			$ref ||= $thing->find;
			if ($ref) {
				my $t = tv_interval($thing->{t}, [ gettimeofday ]);
				if (my $dxc = DXChannel::get($thing->{user} || $thing->{origin})) {
					
					my $tochan = DXChannel::get($thing->{touser} || $thing->{group});
					
					if ($dxc->is_user) {
						my $s = sprintf "%.2f", $t; 
						my $ave = sprintf "%.2f", $tochan ? ($tochan->{pingave} || $t) : $t;
						$dxc->send($dxc->msg('pingi', ($thing->{touser} || $thing->{group}), $s, $ave))
					} elsif ($dxc->is_node) {
						if ($tochan ) {
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
					}
				}
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
	my $call = shift;
	foreach my $thing (values %ping) {
		if (($thing->{user} || $thing->{origin}) eq $call) {
			return $thing;
		}
	}
	return undef;
}
1;
