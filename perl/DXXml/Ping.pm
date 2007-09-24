#
# XML Ping handler
#
#
#
# Copyright (c) Dirk Koopman, G1TLH
#

use strict;

package DXXml::Ping;

use DXDebug;
use DXProt;
use IsoTime;
use Time::HiRes qw(gettimeofday tv_interval);
use Route::Node;

use vars qw(@ISA %pings);
@ISA = qw(DXXml);
%pings = ();                    # outstanding ping requests outbound

sub handle_input
{
	my $self = shift;
	my $dxchan = shift;
	
	if ($self->{to} eq $main::mycall) {
		if ($self->{s} eq '1') {
			my $rep = DXXml::Ping->new(to=>$self->{o}, 
									   s=>'0',
									   oid=>$self->{id},
									   ot=>$self->{t}
									  );
			$dxchan->send($rep->toxml);
			if ($dxchan->{outgoing} && abs($dxchan->{lastping} - $main::systime) < 15) {
				$dxchan->{lastping} += $dxchan->{pingint} / 2; 
			}
		} else {
			handle_ping_reply($dxchan, $self->{o}, $self->{ot}, $self->{oid});
		}
	} else {
		$self->route($dxchan);
	}
}

sub topcxx
{
	my $self = shift;
	unless (exists $self->{'-pcxx'}) {
		$self->{'-pcxx'} = DXProt::pc51($self->{to}, $self->{o}, $self->{s});
	}
	return $self->{'-pcxx'};
}

# add a ping request to the ping queues
sub add
{
	my ($dxchan, $to, $via) = @_;
	my $from = $dxchan->call;
	my $ref = $pings{$to} || [];
	my $r = {};
	my $self = DXXml::Ping->new(to=>$to, '-hirestime'=>[ gettimeofday ], s=>'1');
	$self->{u} = $from unless $from eq $main::mycall;
	$self->{'-via'} = $via if $via && DXChannel::get($via);
	$self->{o} = $main::mycall;
	$self->route($dxchan);

	push @$ref, $self;
	$pings{$to} = $ref;
	my $u = DXUser->get_current($to);
	if ($u) {
		$u->lastping(($via || $from), $main::systime);
		$u->put;
	}
}

sub handle_ping_reply
{
	my $fromdxchan = shift;
	my $from = shift;
	my $ot = shift;
	my $oid = shift;
	my $fromxml;
	
	if (ref $from) {
		$fromxml = $from;
		$from = $from->{o};
	}

	# it's a reply, look in the ping list for this one
	my $ref = $pings{$from};
	return unless $ref;

	my $tochan = DXChannel::get($from);
	while (@$ref) {
		my $r = shift @$ref;
		my $dxchan = DXChannel::get($r->{o});
		next unless $dxchan;
		my $t = tv_interval($r->{'-hirestime'}, [ gettimeofday ]);
		if ($dxchan->is_node) {
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
				dbg("ROUTE: $tochan->{call} ping obscount reset to $tochan->{nopings}") if isdbg('obscount');
				my $nref = Route::Node::get($tochan->{call});
				if ($nref) {
					my $n = $nref->reset_obs;
					dbg("ROUTE: reset obscount on $tochan->{call} to $n (ping)") if isdbg('obscount');
				}
			}
			_handle_believe($from, $fromdxchan->{call});
		} 
		if (exists $r->{u} && ($dxchan = DXChannel::get($r->{u})) && $dxchan->is_user) {
			my $s = sprintf "%.2f", $t; 
			my $ave = sprintf "%.2f", $tochan ? ($tochan->{pingave} || $t) : $t;
			$dxchan->send($dxchan->msg('pingi', $from, $s, $ave))
		} 
	}
}

sub _handle_believe
{
	my ($from, $via) = @_;
	
	my $user = DXUser->get_current($from);
	if ($user) {
		$user->set_believe($via);
		$user->put;
	}
}
1;
