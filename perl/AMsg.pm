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
			$conn->{state} = 'WH';
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
			} elsif ($conn->{state} eq 'WH' ) {
				# this is the first stage that we have a callsign
				# do we have a hello?
				$msg =~ s/[\r\n]+$//;
				if ($msg =~ m{ROUTE,[0-9A-F,]+|HELLO}) {
					# a possibly valid HELLO line, process it
					$conn->new_channel($msg);
				}
			} elsif ($conn->{state} eq 'WC') {
				if (exists $conn->{cmd} && @{$conn->{cmd}}) {
					$conn->_docmd($msg);
					if ($conn->{state} eq 'WC' && exists $conn->{cmd} &&  @{$conn->{cmd}} == 0) {
						$conn->{state} = 'WH';
					}
				}
			}
		}
	} 
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
			$conn->{outbound} = 0;
			$conn->{state} = 'WH';		# wait for return authorize
			my $thing = $conn->{lastthing} = Thingy::Hello->new(origin=>$main::mycall, group=>'ROUTE');

			$thing->send($conn, 'Aranea');
			dbg("-> D $conn->{peerhost} $thing->{Aranea}") if isdbg('chan');
		}
	} else {
		dbg("ExtMsg: error on accept ($!)") if isdbg('err');
	}
}

sub set_newchannel_rproc
{
	my $conn = shift;
	$conn->{rproc} = \&new_channel;
	$conn->{state} = 'WH';
}

# 
# happens next on receive 
#

sub new_channel
{
	my ($conn, $msg) = @_;
	my $call = $conn->{call} || $conn->{peerhost};

	dbg("<- I $call $msg") if isdbg('chan');

	my $thing = Aranea::input($msg);
	unless ($thing) {
		dbg("Invalid thingy: $msg from $conn->{peerhost}");
		$conn->send_now("Sorry");
		$conn->disconnect;
		return;
	}

	$call = $thing->{origin};
	unless (is_callsign($call)) {
		main::already_conn($conn, $call, DXM::msg($main::lang, "illcall", $call));
		return;
	}

	# set up the basic channel info
	# is there one already connected to me - locally? 
	my $user = DXUser->get_current($call);
	my $dxchan = DXChannel->get($call);
	if ($dxchan) {
		if ($main::bumpexisting && $call ne $main::mycall) {
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
	$conn->conns($call);

	# set callbacks
	$conn->set_error(sub {main::error_handler($dxchan)});
	$conn->set_rproc(sub {my ($conn,$msg) = @_; $dxchan->rec($msg)});
	$conn->{state} = 'C';
	delete $conn->{cmd};
	$conn->{timeout}->del if $conn->{timeout};
	delete $conn->{timeout};
	$conn->nolinger;
	$thing->handle($dxchan);
}

sub send
{
	my $conn = shift;
	for (@_) {
		$conn->send_later($_);
	}
}
