#
# This class implements the new style comms for Aranea
# communications for Msg.pm
#
# $Id$
#
# Copyright (c) 2005 - Dirk Koopman G1TLH
#

use strict;

package AMsg;

use Msg;
use DXVars;
use DXUtil;
use DXDebug;
use Aranea;
use Verify;
use DXLog;
use Thingy;
use Thingy::Hello;

use vars qw($VERSION $BRANCH);
$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /\d+\.\d+\.(\d+)\.(\d+)/  || (0,0));
$main::build += $VERSION;
$main::branch += $BRANCH;

use vars qw(@ISA $deftimeout);

@ISA = qw(ExtMsg Msg);
$deftimeout = 60;

sub enqueue
{
	my ($conn, $msg) = @_;
	push (@{$conn->{outqueue}}, $msg . $conn->{lineend});
}

sub dequeue
{
	my $conn = shift;
	my $msg;

	if ($conn->{csort} eq 'ax25' && exists $conn->{msg}) {
		$conn->{msg} =~ s/\cM/\cJ/g;
	}
	if ($conn->{state} eq 'WC' ) {
		if (exists $conn->{cmd}) {
			if (@{$conn->{cmd}}) {
				dbg("connect $conn->{cnum}: $conn->{msg}") if isdbg('connect');
				$conn->_docmd($conn->{msg});
			} 
		}
		if ($conn->{state} eq 'WC' && exists $conn->{cmd} && @{$conn->{cmd}} == 0) {
			$conn->to_connected($conn->{call}, 'O', $conn->{csort});
		}
	} elsif ($conn->{msg} =~ /\cJ/) {
		my @lines =  $conn->{msg} =~ /([^\cM\cJ]*)\cM?\cJ/g;
		if ($conn->{msg} =~ /\cJ$/) {
			delete $conn->{msg};
		} else {
			$conn->{msg} =~ s/([^\cM\cJ]*)\cM?\cJ//g;
		}
		while (defined ($msg = shift @lines)) {
			dbg("connect $conn->{cnum}: $msg") if $conn->{state} ne 'C' && isdbg('connect');
			if ($conn->{state} eq 'C') {
				&{$conn->{rproc}}($conn, $msg);
			} elsif ($conn->{state} eq 'WA' ) {
				my $uref = DXUser->get_current($conn->{call});
				$msg =~ s/[\r\n]+$//;
				if ($uref && $msg eq $uref->passwd) {
					my $sort = $conn->{csort};
					$sort = 'local' if $conn->{peerhost} eq "127.0.0.1";
					$conn->{usedpasswd} = 1;
					$conn->to_connected($conn->{call}, 'A', $sort);
				} else {
					$conn->send_now("Sorry");
					$conn->disconnect;
				}
			} elsif ($conn->{state} eq 'WC') {
				if (exists $conn->{cmd} && @{$conn->{cmd}}) {
					$conn->_docmd($msg);
					if ($conn->{state} eq 'WC' && exists $conn->{cmd} &&  @{$conn->{cmd}} == 0) {
						$conn->to_connected($conn->{call}, 'O', $conn->{csort});
					}
				}
			}
		}
	} 
}

sub to_connected
{
	my ($conn, $call, $dir, $sort) = @_;
	$conn->{state} = 'C';
	$conn->conns($call);
	delete $conn->{cmd};
	$conn->{timeout}->del if $conn->{timeout};
	delete $conn->{timeout};
	$conn->nolinger;
	&{$conn->{rproc}}($conn, "$dir$call|$sort");
}

sub login
{
	return \&new_channel;
}

sub new_client {
	my $server_conn = shift;
    my $sock = $server_conn->{sock}->accept();
	if ($sock) {
		my $conn = $server_conn->new($server_conn->{rproc});
		$conn->{sock} = $sock;
		$conn->nolinger;
		Msg::blocking($sock, 0);
		$conn->{blocking} = 0;
		eval {$conn->{peerhost} = $sock->peerhost};
		if ($@) {
			dbg($@) if isdbg('connll');
			$conn->disconnect;
		} else {
			eval {$conn->{peerport} = $sock->peerport};
			$conn->{peerport} = 0 if $@;
			my ($rproc, $eproc) = &{$server_conn->{rproc}} ($conn, $conn->{peerhost}, $conn->{peerport});
			dbg("accept $conn->{cnum} from $conn->{peerhost} $conn->{peerport}") if isdbg('connll');
			if ($eproc) {
				$conn->{eproc} = $eproc;
				Msg::set_event_handler ($sock, "error" => $eproc);
			}
			if ($rproc) {
				$conn->{rproc} = $rproc;
				my $callback = sub {$conn->_rcv};
				Msg::set_event_handler ($sock, "read" => $callback);
				$conn->_dotimeout(60);
				$conn->{echo} = 0;
			} else { 
				&{$conn->{eproc}}() if $conn->{eproc};
				$conn->disconnect();
			}
			Log('Aranea', "Incoming connection from $conn->{peerhost}");
			$conn->{outgoing} = 0;
			$conn->{state} = 'WH';		# wait for return authorize
			my $thing = $conn->{lastthing} = Thingy::Hello->new(origin=>$main::mycall, group=>'ROUTE');
			$thing->send($conn, 'Aranea');
		}
	} else {
		dbg("ExtMsg: error on accept ($!)") if isdbg('err');
	}
}

sub start_connect
{
	my $call = shift;
	my $fn = shift;
	my $conn = AMsg->new(\&new_channel); 
	$conn->{outgoing} = 1;
	$conn->conns($call);
	
	my $f = new IO::File $fn;
	push @{$conn->{cmd}}, <$f>;
	$f->close;
	$conn->{state} = 'WC';
	$conn->_dotimeout($deftimeout);
	$conn->_docmd;
}

# 
# happens next on receive 
#

sub new_channel
{
	my ($conn, $msg) = @_;
	my $thing = Aranea::input($msg);
	return unless defined $thing;

	my $call = $thing->{origin};
	unless (is_callsign($call)) {
		main::already_conn($conn, $call, DXM::msg($main::lang, "illcall", $call));
		return;
	}

	# set up the basic channel info
	# is there one already connected to me - locally? 
	my $user = DXUser->get_current($call);
	my $dxchan = DXChannel->get($call);
	if ($dxchan) {
		if ($main::bumpexisting) {
			my $ip = $conn->{peerhost} || 'unknown';
			$dxchan->send_now('D', DXM::msg($main::lang, 'conbump', $call, $ip));
			Log('DXCommand', "$call bumped off by $ip, disconnected");
			dbg("$call bumped off by $ip, disconnected");
			$dxchan->disconnect;
		} else {
			main::already_conn($conn, $call, DXM::msg($main::lang, 'conother', $call, $main::mycall));
			return;
		}
	}

	# is he locked out ?
	my $basecall = $call;
	$basecall =~ s/-\d+$//;
	my $baseuser = DXUser->get_current($basecall);
	my $lock = $user->lockout if $user;
	if ($baseuser && $baseuser->lockout || $lock) {
		if (!$user || !defined $lock || $lock) {
			my $host = $conn->{peerhost} || "unknown";
			Log('DXCommand', "$call on $host is locked out, disconnected");
			$conn->disconnect;
			return;
		}
	}
	
	if ($user) {
		$user->{lang} = $main::lang if !$user->{lang}; # to autoupdate old systems
	} else {
		$user = DXUser->new($call);
	}
	
	# create the channel
	$dxchan = Aranea->new($call, $conn, $user);

	# check that the conn has a callsign
	$conn->conns($call) if $conn->isa('IntMsg');

	# set callbacks
	$conn->set_error(sub {main::error_handler($dxchan)});
	$conn->set_rproc(sub {my ($conn,$msg) = @_; $dxchan->rec($msg)});
	$dxchan->rec($msg);
}

sub send
{
	my $conn = shift;
	for (@_) {
		$conn->send_later($_);
	}
}
