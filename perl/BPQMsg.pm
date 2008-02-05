#
# This class is the internal subclass that deals with the G8BPQ switch connections
#
# Written by John Wiseman G8BPQ Jan 2006
#
# Based on AGWMsg.pm Copyright (c) 2001 - Dirk Koopman G1TLH
#

package BPQMsg;

use strict;
use Msg;
use BPQConnect;
use DXDebug;

use vars qw(@ISA @outqueue $send_offset $inmsg $rproc $noports
			%circuit $total_in $total_out);

@ISA = qw(Msg ExtMsg);
@outqueue = ();
$send_offset = 0;
$inmsg = '';
$rproc = undef;
$noports = 0;
%circuit = ();
$total_in = $total_out = 0;

my $GetFreeBuffs;
my $FindFreeStream;
my $SetAppl;
my $SessionState;
my $GetCallsign;
my $SendMsg;
my $GetMsg;
my $RXCount;
my $DeallocateStream;
my $SessionControl;

my @Stream;

my $Buffers;

sub init
{
	return unless $enable;

	eval {
		require Win32::API;
	};
	if ($@) {
		$enable = 0;
		dbg("BPQWin disabled because Win32::API cannot be loaded");
		return;
	} else {
		Win32::API->import;
	}

	$rproc = shift;

	dbg("BPQ initialising...");

	$GetFreeBuffs = Win32::API->new("bpq32", "int _GetFreeBuffs\@0()");
    $FindFreeStream = Win32::API->new("bpq32", "int _FindFreeStream\@0()");
    $SetAppl = Win32::API->new("bpq32", "int _SetAppl\@12(int a, int b, int c)");
    $SessionState = Win32::API->new("bpq32", "DWORD _SessionState\@12(DWORD stream, LPDWORD state, LPDWORD change)");
	$GetCallsign = new Win32::API("bpq32", "_GetCallsign\@8",'NP','N');
	$SendMsg = new Win32::API("bpq32","_SendMsg\@12",'NPN','N');
	$RXCount = new Win32::API("bpq32","_RXCount\@4",'N','N');
	$GetMsg = Win32::API->new("bpq32","_GetMsgPerl\@8",'NP','N');

	$DeallocateStream = Win32::API->new("bpq32","_DeallocateStream\@4",'N','N');
    $SessionControl = Win32::API->new("bpq32", "int _SessionControl\@12(int a, int b, int c)");

	if (!defined $GetMsg) {
		$GetMsg = Win32::API->new("bpqperl","_GetMsgPerl\@8",'NP','N');
	}

	if (!defined $GetMsg) {
		dbg ("Can't find routine 'GetMsgPerl' - is bpqperl.dll available?");
	}

	$Buffers = 0;

	if (defined $GetFreeBuffs && defined $GetMsg) {
		my $s;

		$Buffers = $GetFreeBuffs->Call();

		dbg("G8BPQ Free Buffers = $Buffers") if isdbg('bpq');

		$s = "BPQ Streams:";

		for (my $i = 1; $i <= $BPQStreams; $i++) {

			$Stream[$i] = $FindFreeStream->Call();

			$s .= " $Stream[$i]";

			$SetAppl->Call($Stream[$i], 0, $ApplMask);

		}

		dbg($s) if isdbg('bpq');
	} else {

		dbg("Couldn't initialise BPQ32 switch, BPQ disabled");
		$enable = 0;
	}
}

sub finish
{
	return unless $enable;

	dbg("BPQ Closing..") if isdbg('bpq');

	return unless $Buffers;

	for (my $i = 1; $i <= $BPQStreams; $i++) {
		$SetAppl->Call($Stream[$i], 0, 0);
		$SessionControl->Call($Stream[$i], 2, 0); # Disconnect
		$DeallocateStream->Call($Stream[$i]);
	}
}

sub login
{
	goto &main::login;			# save some writing, this was the default
}

sub active
{
	dbg("BPQ is active called") if isdbg('bpq');
	return $Buffers;
}


sub connect
{

	return unless $Buffers;

	my ($conn, $line) = @_;
	my ($port, $call) = split /\s+/, $line;


	dbg("BPQ Outgoing Connect  $conn $port $call") if isdbg('bpq');


	for (my $i = $BPQStreams; $i > 0; $i--) {
		my $inuse = $circuit{$Stream[$i]};

		if (not $inuse) {		# Active connection?

			dbg("BPQ Outgoing Connect using stream $i") if isdbg('bpq');

			$conn->{bpqstream} = $Stream[$i];
			$conn->{lineend} = "\cM";
			$conn->{incoming} = 0;
			$conn->{csort} = 'ax25';
			$conn->{bpqcall} = uc $call;
			$circuit{$Stream[$i]} = $conn;

			$SessionControl->Call($Stream[$i], 1, 0); # Connect

			$conn->{state} = 'WC';

			return 1;

		}

	}

	# No free streams
	dbg("BPQ Outgoing Connect - No streams available") if isdbg('bpq');

	$conn->{bpqstream} = 0;		# So we can tidy up
	$circuit{0} = $conn;
	return 0;
}

sub in_disconnect
{
	my $conn = shift;
	dbg( "in_disconnect $conn $circuit{$conn->{bpqstream}}") if isdbg('bpq');
	delete $circuit{$conn->{bpqstream}};
	$conn->SUPER::disconnect;
}

sub disconnect
{

	return unless $enable && $Buffers;

	my $conn = shift;

	delete $circuit{$conn->{bpqstream}};

	$conn->SUPER::disconnect;

	if ($conn->{bpqstream}) {	# not if stream = 0!
		$SessionControl->Call($conn->{bpqstream}, 2, 0); # Disconnect
	}
}

sub enqueue
{

	return unless $Buffers;

	my ($conn, $msg) = @_;

	if ($msg =~ /^D/) {
		$msg =~ s/^[-\w]+\|//;
		#		_sendf('Y', $main::mycall, $conn->{call}, $conn->{bpqstream}, $conn->{agwpid});
		#		_sendf('D', $main::mycall, $conn->{bpqcall}, $conn->{bpqstream}, $conn->{agwpid}, $msg . $conn->{lineend});

		$msg = $msg . $conn->{lineend};

		my $len = length($msg);
		$SendMsg->Call($conn->{bpqstream}, $msg, $len);
		dbg("BPQ Data Out port: $conn->{bpqstream}   length: $len \"$msg\"") if isdbg('bpq');
	}
}

sub process
{
	return unless $enable && $Buffers;

	my $state=0;
	my $change=0;

	for (my $i = 1; $i <= $BPQStreams; $i++) {
		$SessionState->Call($Stream[$i], $state, $change);

		if ($change) {
			dbg("Stream $Stream[$i] newstate $state") if isdbg('bpq');

			if ($state == 0) {
				# Disconnected

				my $conn = $circuit{$Stream[$i]};

				if ($conn) {		# Active connection?
					&{$conn->{eproc}}() if $conn->{eproc};
					$conn->in_disconnect;
				}

			}

			if ($state) {

				# Incoming call

				my $call="            ";

				$GetCallsign->Call($Stream[$i],$call);

				for ($call) {	# trim whitespace in $variable, cheap
			        s/^\s+//;
					s/\s+$//;
				}

				dbg("BPQ Connect Stream $Stream[$i] $call") if isdbg('bpq');

				my $conn =  $circuit{$Stream[$i]};;

				if ($conn) {

					# Connection already exists - if we are connecting out this is OK

					if ($conn->{state} eq 'WC') {
						$SendMsg->Call($Stream[$i], "?\r", 2); # Trigger response for chat script
					}

					# Just ignore incomming connect if we think it is already connected

				} else {

					# New Incoming Connect

					$conn = BPQMsg->new($rproc);
					$conn->{bpqstream} = $Stream[$i];
					$conn->{lineend} = "\cM";
					$conn->{incoming} = 1;
					$conn->{bpqcall} = $call;
					$circuit{$Stream[$i]} = $conn;
					if (my ($c, $s) = $call =~ /^(\w+)-(\d\d?)$/) {
						$s = 15 - $s if $s > 8;
						$call = $s > 0 ? "${c}-${s}" : $c;
					}
					$conn->to_connected($call, 'A', $conn->{csort} = 'ax25');
				}

			}

		}

		# See if data received

		my $cnt = $RXCount->Call($Stream[$i]);

		while ($cnt > 0) {
			$cnt--;

			my $Buffer = " " x 340;

			my $len=0;

			$len=$GetMsg->Call($Stream[$i],$Buffer);

			$Buffer = substr($Buffer,0,$len);

			dbg ("BPQ RX: $Buffer") if isdbg('bpq');

			my $conn = $circuit{$Stream[$i]};

			if ($conn) {

				dbg("BPQ State = $conn->{state}") if isdbg('bpq');

				if ($conn->{state} eq 'WC') {
					if (exists $conn->{cmd}) {
						if (@{$conn->{cmd}}) {
							dbg($Buffer) if isdbg('connect');
							$conn->_docmd($Buffer);
						}
					}
					if ($conn->{state} eq 'WC' && exists $conn->{cmd} && @{$conn->{cmd}} == 0) {
						$conn->to_connected($conn->{call}, 'O', $conn->{csort});
					}
				} else {
					my @lines = split /\cM\cJ?/, $Buffer;
					push @lines, $Buffer unless @lines;
					for (@lines) {
						&{$conn->{rproc}}($conn, "I$conn->{call}|$_");
					}
				}
			} else {
				dbg("BPQ error Unsolicited Data!");
			}
		}
	}
}

1;

