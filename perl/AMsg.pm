#
# This class implements the new style comms for Aranea
# communications for Msg.pm
#
# $Id$
#
# Copyright (c) 2001 - Dirk Koopman G1TLH
#

package AMsg;

use strict;
use Msg;
use DXVars;
use DXUtil;
use DXDebug;
use IO::File;
use IO::Socket;
use IPC::Open3;

use vars qw($VERSION $BRANCH);
$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /\d+\.\d+\.(\d+)\.(\d+)/  || (0,0));
$main::build += $VERSION;
$main::branch += $BRANCH;

use vars qw(@ISA $deftimeout);

@ISA = qw(ExtMsg);
$deftimeout = 60;

sub enqueue
{
	my ($conn, $msg) = @_;
	unless ($msg =~ /^[ABZ]/) {
		if ($msg =~ /^E[-\w]+\|([01])/ && $conn->{csort} eq 'telnet') {
			$conn->{echo} = $1;
			if ($1) {
#				$conn->send_raw("\xFF\xFC\x01");
			} else {
#				$conn->send_raw("\xFF\xFB\x01");
			}
		} else {
			$msg =~ s/^[-\w]+\|//;
			push (@{$conn->{outqueue}}, $msg . $conn->{lineend});
		}
	}
}

sub send_raw
{
	my ($conn, $msg) = @_;
    my $sock = $conn->{sock};
    return unless defined($sock);
	push (@{$conn->{outqueue}}, $msg);
	dbg("connect $conn->{cnum}: $msg") if $conn->{state} ne 'C' && isdbg('connect');
    Msg::set_event_handler ($sock, "write" => sub {$conn->_send(0)});
}

sub echo
{
	my $conn = shift;
	$conn->{echo} = shift;
}

sub dequeue
{
	my $conn = shift;
	my $msg;

	if ($conn->{csort} eq 'ax25' && exists $conn->{msg}) {
		$conn->{msg} =~ s/\cM/\cJ/g;
	}
	if ($conn->{state} eq 'WC') {
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
		
			$msg =~ s/\xff\xfa.*\xff\xf0|\xff[\xf0-\xfe].//g; # remove telnet options
#			$msg =~ s/[\x00-\x08\x0a-\x19\x1b-\x1f\x80-\x9f]/./g;         # immutable CSI sequence + control characters
			
			if ($conn->{state} eq 'C') {
				&{$conn->{rproc}}($conn, "I$conn->{call}|$msg");
			} elsif ($conn->{state} eq 'WL' ) {
				$msg = uc $msg;
				if (is_callsign($msg) && $msg !~ m|/| ) {
					my $sort = $conn->{csort};
					$sort = 'local' if $conn->{peerhost} eq "127.0.0.1";
					my $uref;
					if ($main::passwdreq || ($uref = DXUser->get_current($msg)) && $uref->passwd ) {
						$conn->conns($msg);
						$conn->{state} = 'WP';
						$conn->{decho} = $conn->{echo};
						$conn->{echo} = 0;
						$conn->send_raw('password: ');
					} else {
						$conn->to_connected($msg, 'A', $sort);
					}
				} else {
					$conn->send_now("Sorry $msg is an invalid callsign");
					$conn->disconnect;
				}
			} elsif ($conn->{state} eq 'WP' ) {
				my $uref = DXUser->get_current($conn->{call});
				$msg =~ s/[\r\n]+$//;
				if ($uref && $msg eq $uref->passwd) {
					my $sort = $conn->{csort};
					$conn->{echo} = $conn->{decho};
					delete $conn->{decho};
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
	$conn->_send_file("$main::data/connected") unless $conn->{outgoing};
}


