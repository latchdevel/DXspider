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

use vars qw(@ISA @ping);
@ISA = qw(Thingy);

my $id;

sub gen_Aranea
{
	my $thing = shift;
	unless ($thing->{Aranea}) {
	 	$thing->{Aranea} = Aranea::genmsg($thing);
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
	my $thing = ref $_[0] ? shift : $thing->SUPER::new();
	
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
			my $repthing;
			if ($thing->{touser}) {
				if (my $dxchan = DXChannel::get($thing->{touser})) {
					if ($dxchan->is_node) {
						$thing->send($dxchan);
					} else {
						$repthing = Thingy::Ping->new_reply($thing);
					}
				}
			} else {
				$repthing = Thingy::Ping->new_reply($thing);
			}
			$repthing->send($dxchan) if $repthing;
		} else {

			# it's a reply, look in the ping list for this one
			my $ref = $pings{$from};
			if ($ref) {
				my $tochan =  DXChannel::get($from);
				while (@$ref) {
					my $r = shift @$ref;
					my $dxchan = DXChannel::get($r->{call});
					next unless $dxchan;
					my $t = tv_interval($r->{t}, [ gettimeofday ]);
					if ($dxchan->is_user) {
						my $s = sprintf "%.2f", $t; 
						my $ave = sprintf "%.2f", $tochan ? ($tochan->{pingave} || $t) : $t;
						$dxchan->send($dxchan->msg('pingi', $from, $s, $ave))
					} elsif ($dxchan->is_node) {
						if ($tochan) {
							my $nopings = $tochan->user->nopings || $obscount;
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
							if (my $ivp = Investigate::get($from, $origin)) {
								$ivp->handle_ping;
							}
						} elsif (my $rref = Route::Node::get($r->{call})) {
							if (my $ivp = Investigate::get($from, $origin)) {
								$ivp->handle_ping;
							}
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
		$u->lastping(($thing->{group} || $thing->{user}), $main::systime);
		$u->put;
	}
	push @ping, $thing;
}

# remove any pings outstanding that we have remembered for this
# callsign, return the number of forgotten pings
sub forget
{
	my $call = shift;
	my $count = 0;
	my @out;	
	for (@ping) {
		if ($thing->{user} eq $call) {
			$count++;
		} else {
			push @out, $_;
		}
	}
	@ping = @out;
	return $count;
}

sub find
{
	my $from = shift;
	my $to = shift;
	my $via = shift;
	
	for (@ping) {
		if ($_->{user} eq $from && $_->{to} eq $to) {
			if ($via) {
				return $_ if $_->{group} eq $via;
			} else {
				return $_;
			}
		}
	}
	return undef;
}
1;
