#!/usr/bin/perl
#
# This module impliments the protocal mode for a dx cluster
#
# Copyright (c) 1998 Dirk Koopman G1TLH
#
# $Id$
# 

package DXProt;

@ISA = qw(DXChannel);

use DXUtil;
use DXChannel;
use DXUser;
use DXM;
use DXCluster;
use DXProtVars;
use DXCommandmode;
use DXLog;
use Spot;
use DXProtout;
use DXDebug;
use Filter;
use Local;
use DXDb;

use Carp;

use strict;
use vars qw($me $pc11_max_age $pc23_max_age $pc11_dup_age $pc23_dup_age
			%spotdup %wwvdup $last_hour %pings %rcmds
			%nodehops @baddx $baddxfn $pc12_dup_age
			%anndup $allowzero $pc12_dup_lth $decode_dk0wcy);

$me = undef;					# the channel id for this cluster
$decode_dk0wcy = undef;			# if set use this callsign to decode announces from the EU WWV data beacon
$pc11_max_age = 1*3600;			# the maximum age for an incoming 'real-time' pc11
$pc23_max_age = 1*3600;			# the maximum age for an incoming 'real-time' pc23
$pc11_dup_age = 24*3600;		# the maximum time to keep the spot dup list for
$pc23_dup_age = 24*3600;		# the maximum time to keep the wwv dup list for
$pc12_dup_age = 12*3600;		# the maximum time to keep the ann dup list for
$pc12_dup_lth = 72;				# the length of ANN text to save for deduping 
%spotdup = ();				    # the pc11 and 26 dup hash 
%wwvdup = ();				    # the pc23 and 27 dup hash
%anndup = ();                               # the PC12 dup hash
$last_hour = time;				# last time I did an hourly periodic update
%pings = ();                    # outstanding ping requests outbound
%rcmds = ();                    # outstanding rcmd requests outbound
%nodehops = ();                 # node specific hop control
@baddx = ();                    # list of illegal spotted callsigns

$baddxfn = "$main::data/baddx.pl";

sub init
{
	my $user = DXUser->get($main::mycall);
	$DXProt::myprot_version += $main::version*100;
	$me = DXProt->new($main::mycall, 0, $user); 
	$me->{here} = 1;
	$me->{state} = "indifferent";
	do "$main::data/hop_table.pl" if -e "$main::data/hop_table.pl";
	confess $@ if $@;
	#  $me->{sort} = 'M';    # M for me

	# now prime the spot duplicates file with today's and yesterday's data
    my @today = Julian::unixtoj(time);
	my @spots = Spot::readfile(@today);
	@today = Julian::sub(@today, 1);
	push @spots, Spot::readfile(@today);
	for (@spots) {
		my $dupkey = "$_->[0]$_->[1]$_->[2]$_->[3]$_->[4]";
		$spotdup{$dupkey} = $_->[2];
	}

	# now prime the wwv duplicates file with just this month's data
	my @wwv = Geomag::readfile(time);
	for (@wwv) {
		my $dupkey = "$_->[1].$_->[2]$_->[3]$_->[4]";
		$wwvdup{$dupkey} = $_->[1];
	}

	# load the baddx file
	do "$baddxfn" if -e "$baddxfn";
	print "$@\n" if $@;
}

#
# obtain a new connection this is derived from dxchannel
#

sub new 
{
	my $self = DXChannel::alloc(@_);
	$self->{'sort'} = 'A';		# in absence of how to find out what sort of an object I am
	return $self;
}

# this is how a pc connection starts (for an incoming connection)
# issue a PC38 followed by a PC18, then wait for a PC20 (remembering
# all the crap that comes between).
sub start
{
	my ($self, $line, $sort) = @_;
	my $call = $self->{call};
	my $user = $self->{user};
	
	# remember type of connection
	$self->{consort} = $line;
	$self->{outbound} = $sort eq 'O';
	$self->{priv} = $user->priv;
	$self->{lang} = $user->lang;
	$self->{isolate} = $user->{isolate};
	$self->{consort} = $line;	# save the connection type
	$self->{here} = 1;

	# get the INPUT filters (these only pertain to Clusters)
	$self->{inspotfilter} = Filter::read_in('spots', $call, 1);
	$self->{inwwvfilter} = Filter::read_in('wwv', $call, 1);
	$self->{inannfilter} = Filter::read_in('ann', $call, 1);
	
	# set unbuffered and no echo
	$self->send_now('B',"0");
	$self->send_now('E',"0");
	
	# send initialisation string
	if (!$self->{outbound}) {
		$self->send(pc38()) if DXNode->get_all();
		$self->send(pc18());
	}
	$self->state('init');
	$self->pc50_t(time);

	Log('DXProt', "$call connected");
}

#
# This is the normal pcxx despatcher
#
sub normal
{
	my ($self, $line) = @_;
	my @field = split /\^/, $line;
	pop @field if $field[-1] eq '~';
	
#	print join(',', @field), "\n";
						
	# ignore any lines that don't start with PC
	return if !$field[0] =~ /^PC/;
	
	# process PC frames
	my ($pcno) = $field[0] =~ /^PC(\d\d)/; # just get the number
	return unless $pcno;
	return if $pcno < 10 || $pcno > 51;

	# dump bad protocol messages unless it is a PC29
	if ($line =~ /\%[0-9A-F][0-9A-F]/o && $pcno != 29) {
		dbg('chan', "CORRUPT protocol message - dumped");
		return;
	}

	# local processing 1
	my $pcr;
	eval {
		$pcr = Local::pcprot($self, $pcno, @field);
	};
#	dbg('local', "Local::pcprot error $@") if $@;
	return if $pcr;
	
 SWITCH: {
		if ($pcno == 10) {		# incoming talk
			
			# is it for me or one of mine?
			my $call = ($field[5] gt ' ') ? $field[5] : $field[2];
			if ($call eq $main::mycall || grep $_ eq $call, get_all_user_calls()) {
				
				# yes, it is
				my $text = unpad($field[3]);
				Log('talk', $call, $field[1], $field[6], $text);
				$call = $main::myalias if $call eq $main::mycall;
				my $ref = DXChannel->get($call);
				$ref->send("$call de $field[1]: $text") if $ref && $ref->{talk};
			} else {
				$self->route($field[2], $line); # relay it on its way
			}
			return;
		}
		
		if ($pcno == 11 || $pcno == 26) { # dx spot

			# route 'foreign' pc26s 
			if ($pcno == 26) {
				if ($field[7] ne $main::mycall) {
					$self->route($field[7], $line);
					return;
				}
			}
			
			# if this is a 'nodx' node then ignore it
			if (grep $field[7] =~ /^$_/,  @DXProt::nodx_node) {
				dbg('chan', "Bad DXNode, dropped");
				return;
			}
			
			# convert the date to a unix date
			my $d = cltounix($field[3], $field[4]);
			# bang out (and don't pass on) if date is invalid or the spot is too old (or too young)
			if (!$d || ($pcno == 11 && ($d < $main::systime - $pc11_max_age || $d > $main::systime + 900))) {
				dbg('chan', "Spot ignored, invalid date or out of range ($field[3] $field[4])\n");
				return;
			}

			# strip off the leading & trailing spaces from the comment
			my $text = unpad($field[5]);
			
			# store it away
			my $spotter = $field[6];
			$spotter =~ s/-[\@\d]+$//o;	# strip off the ssid from the spotter
			
			# do some de-duping
			my $freq = $field[1] - 0;
			my $dupkey = "$freq$field[2]$d$text$spotter";
			if ($spotdup{$dupkey}) {
				dbg('chan', "Duplicate Spot ignored\n");
				return;
			}
			
			$spotdup{$dupkey} = $d;

			# is it 'baddx'
			if (grep $field[2] eq $_, @baddx) {
				dbg('chan', "Bad DX spot, ignored");
				return;
			}

			# are any of the crucial fields invalid?
            if ($field[2] =~ /[a-z]/ || $field[6] =~ /[a-z]/ || $field[7] =~ /[a-z]/) {
				dbg('chan', "Spot contains lower case callsigns, rejected");
				return;
			}
			
			my @spot = Spot::add($freq, $field[2], $d, $text, $spotter, $field[7]);

            #
			# @spot at this point contains:-
            # freq, spotted call, time, text, spotter, spotted cc, spotters cc, orig node
			# then  spotted itu, spotted cq, spotters itu, spotters cq
			# you should be able to route on any of these
            #
			
			# local processing 
			my $r;
			eval {
				$r = Local::spot($self, @spot);
			};
#			dbg('local', "Local::spot1 error $@") if $@;
			return if $r;

			# DON'T be silly and send on PC26s!
			return if $pcno == 26;

			# send out the filtered spots
			send_dx_spot($self, $line, @spot) if @spot;
			return;
		}
		
		if ($pcno == 12) {		# announces
			# announce duplicate checking
			my $text = substr(uc unpad($field[3]), 0, $pc12_dup_lth);
			my $dupkey = $field[1].$field[2].$text;
			if ($anndup{$dupkey}) {
				dbg('chan', "Duplicate Announce ignored\n");
				return;
			}
			$anndup{$dupkey} = $main::systime;
			
			if ($field[2] eq '*' || $field[2] eq $main::mycall) {
				
				# global ann filtering on INPUT
				if ($self->{inannfilter}) {
					my ($filter, $hops) = Filter::it($self->{inannfilter}, @field[1..6], $self->{call} );
					unless ($filter) {
						dbg('chan', "Rejected by filter");
						return;
					}
				}

				# send it
				$self->send_announce($line, @field[1..6]);
				
				if ($decode_dk0wcy && $field[1] eq $decode_dk0wcy) {
					my ($hour, $k, $next, $a, $r, $sfi, $alarm) = $field[3] =~ /^Aurora Beacon\s+(\d+)UTC,\s+Kiel\s+K=(\d+),.*ed\s+K=(\d+),\s+A=(\d+),\s+R=(\d+),\s+SFI=(\d+),.*larm:\s+(\w+)/;
					$alarm = ($alarm =~ /^Y/i) ? ', Aurora in DE' : ''; 
					my $wwv = Geomag::update($main::systime, $hour, $sfi, $a, $k, "R=$r, Next K=$next$alarm", $decode_dk0wcy, $field[5], $r) if $sfi && $r;
				}
				
			} else {
				$self->route($field[2], $line);
			}
			
			return;
		}
		
		if ($pcno == 13) {
			last SWITCH;
		}
		if ($pcno == 14) {
			last SWITCH;
		}
		if ($pcno == 15) {
			last SWITCH;
		}
		
		if ($pcno == 16) {		# add a user
			my $node = DXCluster->get_exact($field[1]); 
			my $dxchan;
			if (!$node && ($dxchan = DXChannel->get($field[1]))) {
				# add it to the node table if it isn't present and it's
				# connected locally
				$node = DXNode->new($dxchan, $field[1], 0, 1, 5400);
				broadcast_ak1a(pc19($dxchan, $node), $dxchan, $self) unless $dxchan->{isolate};
				
			}
			return unless $node; # ignore if havn't seen a PC19 for this one yet
			return unless $node->isa('DXNode');
			if ($node->dxchan != $self) {
				dbg('chan', "LOOP: $field[1] came in on wrong channel");
				return;
			}
			if (($dxchan = DXChannel->get($field[1])) && $dxchan != $self) {
				dbg('chan', "LOOP: $field[1] connected locally");
				return;
			}
			my $i;
						
			for ($i = 2; $i < $#field; $i++) {
				my ($call, $confmode, $here) = $field[$i] =~ /^(\S+) (\S) (\d)/o;
				next if !$call || length $call < 3 || length $call > 8;
				next if !$confmode;
				$call = uc $call;
				next if DXCluster->get_exact($call); # we already have this (loop?)
				
				$confmode = $confmode eq '*';
				DXNodeuser->new($self, $node, $call, $confmode, $here);
				
				# add this station to the user database, if required
				$call =~ s/-\d+$//o;        # remove ssid for users
				my $user = DXUser->get_current($call);
				$user = DXUser->new($call) if !$user;
				$user->homenode($node->call) if !$user->homenode;
				$user->node($node->call);
				$user->lastin($main::systime) unless DXChannel->get($call);
				$user->put;
			}
			
			# queue up any messages (look for privates only)
			DXMsg::queue_msg(1) if $self->state eq 'normal';     
			last SWITCH;
		}
		
		if ($pcno == 17) {		# remove a user
			my $node = DXCluster->get_exact($field[2]);
			my $dxchan;
			if (!$node && ($dxchan = DXChannel->get($field[2]))) {
				# add it to the node table if it isn't present and it's
				# connected locally
				$node = DXNode->new($dxchan, $field[2], 0, 1, 5400);
				broadcast_ak1a(pc19($dxchan, $node), $dxchan, $self) unless $dxchan->{isolate};
				return;
			}
			return unless $node;
			return unless $node->isa('DXNode');
			if ($node->dxchan != $self) {
				dbg('chan', "LOOP: $field[2] came in on wrong channel");
				return;
			}
			if (($dxchan = DXChannel->get($field[2])) && $dxchan != $self) {
				dbg('chan', "LOOP: $field[2] connected locally");
				return;
			}
			my $ref = DXCluster->get_exact($field[1]);
			$ref->del() if $ref;
			last SWITCH;
		}
		
		if ($pcno == 18) {		# link request
			$self->state('init');	

			# first clear out any nodes on this dxchannel
			my @gonenodes = map { $_->dxchan == $self ? $_ : () } DXNode::get_all();
			foreach my $node (@gonenodes) {
				next if $node->dxchan == $DXProt::me;
				broadcast_ak1a(pc21($node->call, 'Gone, re-init') , $self) unless $self->{isolate}; 
				$node->del();
			}
			$self->send_local_config();
			$self->send(pc20());
			return;             # we don't pass these on
		}
		
		if ($pcno == 19) {		# incoming cluster list
			my $i;
			my $newline = "PC19^";
			for ($i = 1; $i < $#field-1; $i += 4) {
				my $here = $field[$i];
				my $call = uc $field[$i+1];
				my $confmode = $field[$i+2];
				my $ver = $field[$i+3];

				$ver = 5400 if !$ver && $allowzero;
				
				# now check the call over
				my $node = DXCluster->get_exact($call);
				if ($node) {
					my $dxchan;
					if (($dxchan = DXChannel->get($call)) && $dxchan != $self) {
						dbg('chan', "LOOP: $call connected locally");
					}
				    if ($node->dxchan != $self) {
						dbg('chan', "LOOP: $call come in on wrong channel");
						next;
					}
					dbg('chan', "already have $call");
					next;
				}
				
				# check for sane parameters
				next if $ver < 5000; # only works with version 5 software
				next if length $call < 3; # min 3 letter callsigns

				# add it to the nodes table and outgoing line
				$newline .= "$here^$call^$confmode^$ver^";
				DXNode->new($self, $call, $confmode, $here, $ver);
				
				# unbusy and stop and outgoing mail (ie if somehow we receive another PC19 without a disconnect)
				my $mref = DXMsg::get_busy($call);
				$mref->stop_msg($call) if $mref;
				
				# add this station to the user database, if required (don't remove SSID from nodes)
				my $user = DXUser->get_current($call);
				if (!$user) {
					$user = DXUser->new($call);
					$user->sort('A');
					$user->priv(1);                   # I have relented and defaulted nodes
					$self->{priv} = 1;                # to user RCMDs allowed
					$user->homenode($call);
					$user->node($call);
				}
				$user->lastin($main::systime) unless DXChannel->get($call);
				$user->put;
			}
			
			return if $newline eq "PC19^";

			# add hop count 
			$newline .=  get_hops(19) . "^";
			$line = $newline;
			last SWITCH;
		}
		
		if ($pcno == 20) {		# send local configuration
			$self->send_local_config();
			$self->send(pc22());
			$self->state('normal');
			return;
		}
		
		if ($pcno == 21) {		# delete a cluster from the list
			my $call = uc $field[1];
			if ($call ne $main::mycall) { # don't allow malicious buggers to disconnect me!
				my $node = DXCluster->get_exact($call);
				if ($node) {
					if ($node->dxchan != $self) {
						dbg('chan', "LOOP: $call come in on wrong channel");
						return;
					}
					my $dxchan;
					if (($dxchan = DXChannel->get($call)) && $dxchan != $self) {
						dbg('chan', "LOOP: $call connected locally");
						return;
					}
					$node->del();
				} else {
					dbg('chan', "$call not in table, dropped");
					return;
				}
			}
			last SWITCH;
		}
		
		if ($pcno == 22) {
			$self->state('normal');
			return;
		}
				
		if ($pcno == 23 || $pcno == 27) { # WWV info
			
			# route 'foreign' pc27s 
			if ($pcno == 27) {
				if ($field[8] ne $main::mycall) {
					$self->route($field[8], $line);
					return;
				}
			}

			# do some de-duping
			my $d = cltounix($field[1], sprintf("%02d18Z", $field[2]));
			my $sfi = unpad($field[3]);
			my $k = unpad($field[4]);
			my $i = unpad($field[5]);
			my ($r) = $field[6] =~ /R=(\d+)/;
			$r = 0 unless $r;
			my $dupkey = "$d.$sfi$k$i";
			if ($wwvdup{$dupkey}) {
				dbg('chan', "Dup WWV Spot ignored\n");
				return;
			}
			if (($pcno == 23 && $d < $main::systime - $pc23_max_age) || $d > $main::systime + 1500 || $field[2] < 0 || $field[2] > 23) {
				dbg('chan', "WWV Date ($field[1] $field[2]) out of range");
				return;
			}
			$wwvdup{$dupkey} = $d;
			$field[6] =~ s/-\d+$//o;            # remove spotter's ssid
		
			my $wwv = Geomag::update($d, $field[2], $sfi, $k, $i, @field[6..8], $r);

			my $rep;
			eval {
				$rep = Local::wwv($self, $field[1], $field[2], $sfi, $k, $i, @field[6..8], $r);
			};
#			dbg('local', "Local::wwv2 error $@") if $@;
			return if $rep;

			# DON'T be silly and send on PC27s!
			return if $pcno == 27;

			# broadcast to the eager world
			send_wwv_spot($self, $line, $d, $field[2], $sfi, $k, $i, @field[6..8]);
			return;
		}
		
		if ($pcno == 24) {		# set here status
			my $call = uc $field[1];
			my $ref = DXCluster->get_exact($call);
			$ref->here($field[2]) if $ref;
			last SWITCH;
		}
		
		if ($pcno == 25) {      # merge request
			if ($field[1] ne $main::mycall) {
				$self->route($field[1], $line);
				return;
			}
			if ($field[2] eq $main::mycall) {
				dbg('chan', "Trying to merge to myself, ignored");
				return;
			}

			Log('DXProt', "Merge request for $field[3] spots and $field[4] WWV from $field[1]");
			
			# spots
			if ($field[3] > 0) {
				my @in = reverse Spot::search(1, undef, undef, 0, $field[3]);
				my $in;
				foreach $in (@in) {
					$self->send(pc26(@{$in}[0..4], $field[2]));
				}
			}

			# wwv
			if ($field[4] > 0) {
				my @in = reverse Geomag::search(0, $field[4], time, 1);
				my $in;
				foreach $in (@in) {
					$self->send(pc27(@{$in}[0..5], $field[2]));
				}
			}
			return;
		}

		if (($pcno >= 28 && $pcno <= 33) || $pcno == 40 || $pcno == 42 || $pcno == 49) { # mail/file handling
			if ($pcno == 49 || $field[1] eq $main::mycall) {
				DXMsg::process($self, $line);
			} else {
				$self->route($field[1], $line);
			}
			return;
		}
		
		if ($pcno == 34 || $pcno == 36) { # remote commands (incoming)
			if ($field[1] eq $main::mycall) {
				my $ref = DXUser->get_current($field[2]);
				my $cref = DXCluster->get($field[2]);
				Log('rcmd', 'in', $ref->{priv}, $field[2], $field[3]);
				unless ($field[3] =~ /rcmd/i || !$cref || !$ref || $cref->mynode->call ne $ref->homenode) {    # not allowed to relay RCMDS!
					if ($ref->{priv}) {	# you have to have SOME privilege, the commands have further filtering
						$self->{remotecmd} = 1; # for the benefit of any command that needs to know
						my $oldpriv = $self->{priv};
						$self->{priv} = $ref->{priv};     # assume the user's privilege level
						my @in = (DXCommandmode::run_cmd($self, $field[3]));
						$self->{priv} = $oldpriv;
						for (@in) {
							s/\s*$//og;
							$self->send(pc35($main::mycall, $field[2], "$main::mycall:$_"));
							Log('rcmd', 'out', $field[2], $_);
						}
						delete $self->{remotecmd};
					} else {
						$self->send(pc35($main::mycall, $field[2], "$main::mycall:sorry...!"));
					}
				} else {
					$self->send(pc35($main::mycall, $field[2], "$main::mycall:your attempt is logged, Tut tut tut...!"));
				}
			} else {
				$self->route($field[1], $line);
			}
			return;
		}
		
		if ($pcno == 35) {		# remote command replies
			if ($field[1] eq $main::mycall) {
				my $s = $rcmds{$field[2]};
				if ($s) {
					my $dxchan = DXChannel->get($s->{call});
					$dxchan->send($field[3]) if $dxchan;
					delete $rcmds{$field[2]} if !$dxchan;
				}
			} else {
				$self->route($field[1], $line);
			}
			return;
		}
		
		# for pc 37 see 44 onwards

		if ($pcno == 38) {		# node connected list from neighbour
			return;
		}
		
		if ($pcno == 39) {		# incoming disconnect
			$self->disconnect();
			return;
		}
		
		if ($pcno == 41) {		# user info
			# add this station to the user database, if required
			my $user = DXUser->get_current($field[1]);
			if (!$user) {
				# then try without an SSID
				$field[1] =~ s/-\d+$//o;
				$user = DXUser->get_current($field[1]);
			}
			$user = DXUser->new($field[1]) if !$user;
			
			if ($field[2] == 1) {
				$user->name($field[3]);
			} elsif ($field[2] == 2) {
				$user->qth($field[3]);
			} elsif ($field[2] == 3) {
				my ($lat, $long) = DXBearing::stoll($field[3]);
				$user->lat($lat);
				$user->long($long);
			} elsif ($field[2] == 4) {
				$user->homenode($field[3]);
			}
			$user->put;
			last SWITCH;
		}
		if ($pcno == 43) {
			last SWITCH;
		}
		if ($pcno == 37 || $pcno == 44 || $pcno == 45 || $pcno == 46 || $pcno == 47) {
			DXDb::process($self, $line);
			return;
		}
		
		if ($pcno == 50) {		# keep alive/user list
			my $node = DXCluster->get_exact($field[1]);
			if ($node) {
				return unless $node->isa('DXNode');
				return unless $node->dxchan == $self;
				$node->update_users($field[2]);
			}
			last SWITCH;
		}
		
		if ($pcno == 51) {		# incoming ping requests/answers
			
			# is it for us?
			if ($field[1] eq $main::mycall) {
				my $flag = $field[3];
				if ($flag == 1) {
					$self->send(pc51($field[2], $field[1], '0'));
				} else {
					# it's a reply, look in the ping list for this one
					my $ref = $pings{$field[2]};
					if ($ref) {
						while (@$ref) {
							my $r = shift @$ref;
							my $dxchan = DXChannel->get($r->{call});
							$dxchan->send($dxchan->msg('pingi', $field[2], atime($main::systime), $main::systime - $r->{t})) if $dxchan;
						}
					}
				}
				
			} else {
				# route down an appropriate thingy
				$self->route($field[1], $line);
			}
			return;
		}
	}
	 
	 # if get here then rebroadcast the thing with its Hop count decremented (if
	 # there is one). If it has a hop count and it decrements to zero then don't
	 # rebroadcast it.
	 #
	 # NOTE - don't arrive here UNLESS YOU WANT this lump of protocol to be
	 #        REBROADCAST!!!!
	 #
	 
	unless ($self->{isolate}) {
		broadcast_ak1a($line, $self); # send it to everyone but me
	}
}

#
# This is called from inside the main cluster processing loop and is used
# for despatching commands that are doing some long processing job
#
sub process
{
	my $t = time;
	my @dxchan = DXChannel->get_all();
	my $dxchan;
	
	foreach $dxchan (@dxchan) {
		next unless $dxchan->is_ak1a();
		next if $dxchan == $me;
		
		# send a pc50 out on this channel
		if ($t >= $dxchan->pc50_t + $DXProt::pc50_interval) {
			$dxchan->send(pc50());
			$dxchan->pc50_t($t);
		} 
	}
	
	my $key;
	my $val;
	my $cutoff;
	if ($main::systime - 3600 > $last_hour) {
		$cutoff  = $main::systime - $pc11_dup_age;
		while (($key, $val) = each %spotdup) {
			delete $spotdup{$key} if $val < $cutoff;
		}
		$cutoff = $main::systime - $pc23_dup_age;
		while (($key, $val) = each %wwvdup) {
			delete $wwvdup{$key} if $val < $cutoff;
		}
		$cutoff = $main::systime - $pc12_dup_age;
		while (($key, $val) = each %anndup) {
			delete $anndup{$key} if $val < $cutoff;
		}
		$last_hour = $main::systime;
	}
}

#
# finish up a pc context
#
sub finish
{
	my $self = shift;
	my $call = $self->call;
	my $ref = DXCluster->get_exact($call);
	
	# unbusy and stop and outgoing mail
	my $mref = DXMsg::get_busy($call);
	$mref->stop_msg($call) if $mref;
	
	# broadcast to all other nodes that all the nodes connected to via me are gone
	my @gonenodes = map { $_->dxchan == $self ? $_ : () } DXNode::get_all();
	my $node;
	
	foreach $node (@gonenodes) {
		next if $node->call eq $call;
		broadcast_ak1a(pc21($node->call, 'Gone') , $self) unless $self->{isolate}; 
		$node->del();
	}

	# remove outstanding pings
	delete $pings{$call};
	
	# now broadcast to all other ak1a nodes that I have gone
	broadcast_ak1a(pc21($call, 'Gone.'), $self) unless $self->{isolate};
	
	Log('DXProt', $call . " Disconnected");
	$ref->del() if $ref;
}

#
# some active measures
#
sub send_dx_spot
{
	my $self = shift;
	my $line = shift;
	my @dxchan = DXChannel->get_all();
	my $dxchan;
	
	# send it if it isn't the except list and isn't isolated and still has a hop count
	# taking into account filtering and so on
	foreach $dxchan (@dxchan) {
		my $routeit;
		my ($filter, $hops);

		if ($dxchan->{spotfilter}) {
		    ($filter, $hops) = Filter::it($dxchan->{spotfilter}, @_, $self->{call} );
			next unless $filter;
		}
		
		if ($dxchan->is_ak1a) {
			next if $dxchan == $self;
			if ($hops) {
				$routeit = $line;
				$routeit =~ s/\^H\d+\^\~$/\^H$hops\^\~/;
			} else {
				$routeit = adjust_hops($dxchan, $line);  # adjust its hop count by node name
				next unless $routeit;
			}
			if ($filter) {
				$dxchan->send($routeit) if $routeit;
			} else {
				$dxchan->send($routeit) unless $dxchan->{isolate} || $self->{isolate};
			}
		} elsif ($dxchan->is_user && $dxchan->{dx}) {
			my $buf = Spot::formatb($_[0], $_[1], $_[2], $_[3], $_[4]);
			$buf .= "\a\a" if $dxchan->{beep};
			if ($dxchan->{state} eq 'prompt' || $dxchan->{state} eq 'convers') {
				$dxchan->send($buf);
			} else {
				$dxchan->delay($buf);
			}
		}					
	}
}

sub send_wwv_spot
{
	my $self = shift;
	my $line = shift;
	my @dxchan = DXChannel->get_all();
	my $dxchan;
	
	# send it if it isn't the except list and isn't isolated and still has a hop count
	# taking into account filtering and so on
	foreach $dxchan (@dxchan) {
		my $routeit;
		my ($filter, $hops);

		if ($dxchan->{spotfilter}) {
			 ($filter, $hops) = Filter::it($dxchan->{wwvfilter}, @_, $self->{call} );
			 next unless $filter;
		}
		if ($dxchan->is_ak1a) {
			next if $dxchan == $self;
			if ($hops) {
				$routeit = $line;
				$routeit =~ s/\^H\d+\^\~$/\^H$hops\^\~/;
			} else {
				$routeit = adjust_hops($dxchan, $line);  # adjust its hop count by node name
				next unless $routeit;
			}
			if ($filter) {
				$dxchan->send($routeit) if $routeit;
			} else {
				$dxchan->send($routeit) unless $dxchan->{isolate} || $self->{isolate};
				
			}
		} elsif ($dxchan->is_user && $dxchan->{wwv}) {
			my $buf = "WWV de $_[6] <$_[1]>:   SFI=$_[2], A=$_[3], K=$_[4], $_[5]";
			$buf .= "\a\a" if $dxchan->{beep};
			if ($dxchan->{state} eq 'prompt' || $dxchan->{state} eq 'convers') {
				$dxchan->send($buf);
			} else {
				$dxchan->delay($buf);
			}
		}					
	}
}

# send an announce
sub send_announce
{
	my $self = shift;
	my $line = shift;
	my @dxchan = DXChannel->get_all();
	my $dxchan;
	my $text = unpad($_[2]);
	my $target;
	my $to = 'To ';
				
	if ($_[3] eq '*') {	# sysops
		$target = "SYSOP";
	} elsif ($_[3] gt ' ') { # speciality list handling
		my ($name) = split /\./, $_[3]; 
		$target = "$name"; # put the rest in later (if bothered) 
	} 
	
	if ($_[5] eq '1') {
		$target = "WX"; 
		$to = '';
	}
	$target = "All" if !$target;
	
	Log('ann', $target, $_[0], $text);

	# send it if it isn't the except list and isn't isolated and still has a hop count
	# taking into account filtering and so on
	foreach $dxchan (@dxchan) {
		my $routeit;
		my ($filter, $hops);

		if ($dxchan->{annfilter}) {
			($filter, $hops) = Filter::it($dxchan->{annfilter}, @_, $self->{call} );
			next unless $filter;
		} 
		if ($dxchan->is_ak1a && $_[1] ne $main::mycall) {  # i.e not specifically routed to me
			next if $dxchan == $self;
			if ($hops) {
				$routeit = $line;
				$routeit =~ s/\^H\d+\^\~$/\^H$hops\^\~/;
			} else {
				$routeit = adjust_hops($dxchan, $line);  # adjust its hop count by node name
				next unless $routeit;
			}
			if ($filter) {
				$dxchan->send($routeit) if $routeit;
			} else {
				$dxchan->send($routeit) unless $dxchan->{isolate} || $self->{isolate};
				
			}
		} elsif ($dxchan->is_user && $dxchan->{ann}) {
			next if $target eq 'SYSOP' && $dxchan->{priv} < 5;
			my $buf = "$to$target de $_[0]: $text";
			$buf .= "\a\a" if $dxchan->{beep};
			if ($dxchan->{state} eq 'prompt' || $dxchan->{state} eq 'convers') {
				$dxchan->send($buf);
			} else {
				$dxchan->delay($buf);
			}
		}					
	}
}

sub send_local_config
{
	my $self = shift;
	my $n;
	my @nodes;
	my @localnodes;
	my @remotenodes;
		
	# send our nodes
	if ($self->{isolate}) {
		@localnodes = (DXCluster->get_exact($main::mycall));
	} else {
		# create a list of all the nodes that are not connected to this connection
		# and are not themselves isolated, this to make sure that isolated nodes
        # don't appear outside of this node
		@nodes = DXNode::get_all();
		@nodes = grep { $_->{call} ne $main::mycall } @nodes;
		@nodes = grep { $_->dxchan != $self } @nodes if @nodes;
		@nodes = grep { !$_->dxchan->{isolate} } @nodes if @nodes;
		@localnodes = grep { $_->dxchan->{call} eq $_->{call} } @nodes if @nodes;
		unshift @localnodes, DXCluster->get_exact($main::mycall);
		@remotenodes = grep { $_->dxchan->{call} ne $_->{call} } @nodes if @nodes;
	}

	my @s = $me->pc19(@localnodes, @remotenodes);
	for (@s) {
		my $routeit = adjust_hops($self, $_);
		$self->send($routeit) if $routeit;
	}
	
	# get all the users connected on the above nodes and send them out
	foreach $n (@localnodes, @remotenodes) {
		my @users = values %{$n->list};
		my @s = pc16($n, @users);
		for (@s) {
			my $routeit = adjust_hops($self, $_);
			$self->send($routeit) if $routeit;
		}
	}
}

#
# route a message down an appropriate interface for a callsign
#
# is called route(to, pcline);
#
sub route
{
	my ($self, $call, $line) = @_;
	my $cl = DXCluster->get_exact($call);
	if ($cl) {       # don't route it back down itself
		if (ref $self && $call eq $self->{call}) {
			dbg('chan', "Trying to route back to source, dropped");
			return;
		}
		my $hops;
		my $dxchan = $cl->{dxchan};
		if ($dxchan) {
			my $routeit = adjust_hops($dxchan, $line);   # adjust its hop count by node name
			if ($routeit) {
				$dxchan->send($routeit) if $dxchan;
			}
		}
	}
}

# broadcast a message to all clusters taking into account isolation
# [except those mentioned after buffer]
sub broadcast_ak1a
{
	my $s = shift;				# the line to be rebroadcast
	my @except = @_;			# to all channels EXCEPT these (dxchannel refs)
	my @dxchan = get_all_ak1a();
	my $dxchan;
	
	# send it if it isn't the except list and isn't isolated and still has a hop count
	foreach $dxchan (@dxchan) {
		next if grep $dxchan == $_, @except;
		my $routeit = adjust_hops($dxchan, $s);      # adjust its hop count by node name
		$dxchan->send($routeit) unless $dxchan->{isolate} || !$routeit;
	}
}

# broadcast a message to all clusters ignoring isolation
# [except those mentioned after buffer]
sub broadcast_all_ak1a
{
	my $s = shift;				# the line to be rebroadcast
	my @except = @_;			# to all channels EXCEPT these (dxchannel refs)
	my @dxchan = get_all_ak1a();
	my $dxchan;
	
	# send it if it isn't the except list and isn't isolated and still has a hop count
	foreach $dxchan (@dxchan) {
		next if grep $dxchan == $_, @except;
		my $routeit = adjust_hops($dxchan, $s);      # adjust its hop count by node name
		$dxchan->send($routeit);
	}
}

# broadcast to all users
# storing the spot or whatever until it is in a state to receive it
sub broadcast_users
{
	my $s = shift;				# the line to be rebroadcast
	my $sort = shift;           # the type of transmission
	my $fref = shift;           # a reference to an object to filter on
	my @except = @_;			# to all channels EXCEPT these (dxchannel refs)
	my @dxchan = get_all_users();
	my $dxchan;
	my @out;
	
	foreach $dxchan (@dxchan) {
		next if grep $dxchan == $_, @except;
		push @out, $dxchan;
	}
	broadcast_list($s, $sort, $fref, @out);
}

# broadcast to a list of users
sub broadcast_list
{
	my $s = shift;
	my $sort = shift;
	my $fref = shift;
	my $dxchan;
	
	foreach $dxchan (@_) {
		my $filter = 1;
		
		if ($sort eq 'dx') {
		    next unless $dxchan->{dx};
			($filter) = Filter::it($dxchan->{spotfilter}, @{$fref}) if ref $fref;
			next unless $filter;
		}
		next if $sort eq 'ann' && !$dxchan->{ann};
		next if $sort eq 'wwv' && !$dxchan->{wwv};
		next if $sort eq 'wx' && !$dxchan->{wx};

		$s =~ s/\a//og unless $dxchan->{beep};

		if ($dxchan->{state} eq 'prompt' || $dxchan->{state} eq 'convers') {
			$dxchan->send($s);	
		} else {
			$dxchan->delay($s);
		}
	}
}

#
# gimme all the ak1a nodes
#
sub get_all_ak1a
{
	my @list = DXChannel->get_all();
	my $ref;
	my @out;
	foreach $ref (@list) {
		push @out, $ref if $ref->is_ak1a;
	}
	return @out;
}

# return a list of all users
sub get_all_users
{
	my @list = DXChannel->get_all();
	my $ref;
	my @out;
	foreach $ref (@list) {
		push @out, $ref if $ref->is_user;
	}
	return @out;
}

# return a list of all user callsigns
sub get_all_user_calls
{
	my @list = DXChannel->get_all();
	my $ref;
	my @out;
	foreach $ref (@list) {
		push @out, $ref->call if $ref->is_user;
	}
	return @out;
}

#
# obtain the hops from the list for this callsign and pc no 
#

sub get_hops
{
	my $pcno = shift;
	my $hops = $DXProt::hopcount{$pcno};
	$hops = $DXProt::def_hopcount if !$hops;
	return "H$hops";       
}

# 
# adjust the hop count on a per node basis using the user loadable 
# hop table if available or else decrement an existing one
#

sub adjust_hops
{
	my $self = shift;
	my $s = shift;
	my $call = $self->{call};
	my $hops;
	
	if (($hops) = $s =~ /\^H(\d+)\^~?$/o) {
		my ($pcno) = $s =~ /^PC(\d\d)/o;
		confess "$call called adjust_hops with '$s'" unless $pcno;
		my $ref = $nodehops{$call} if %nodehops;
		if ($ref) {
			my $newhops = $ref->{$pcno};
			return "" if defined $newhops && $newhops == 0;
			$newhops = $ref->{default} unless $newhops;
			return "" if defined $newhops && $newhops == 0;
			$newhops = $hops if !$newhops;
			$s =~ s/\^H(\d+)(\^~?)$/\^H$newhops$2/ if $newhops;
		} else {
			# simply decrement it
			$hops--;
			return "" if !$hops;
			$s =~ s/\^H(\d+)(\^~?)$/\^H$hops$2/ if $hops;
		}
	}
	return $s;
}

# 
# load hop tables
#
sub load_hops
{
	my $self = shift;
	return $self->msg('lh1') unless -e "$main::data/hop_table.pl";
	do "$main::data/hop_table.pl";
	return $@ if $@;
	return 0;
}

# remove leading and trailing spaces from an input string
sub unpad
{
	my $s = shift;
	$s =~ s/^\s+|\s+$//;
	return $s;
}

# add a ping request to the ping queues
sub addping
{
	my ($from, $to) = @_;
	my $ref = $pings{$to};
	$ref = $pings{$to} = [] if !$ref;
	my $r = {};
	$r->{call} = $from;
	$r->{t} = $main::systime;
	route(undef, $to, pc51($to, $main::mycall, 1));
	push @$ref, $r;
}

# add a rcmd request to the rcmd queues
sub addrcmd
{
	my ($from, $to, $cmd) = @_;
	my $r = {};
	$r->{call} = $from;
	$r->{t} = $main::systime;
	$r->{cmd} = $cmd;
	route(undef, $to, pc34($main::mycall, $to, $cmd));
	$rcmds{$to} = $r;
}
1;
__END__ 
