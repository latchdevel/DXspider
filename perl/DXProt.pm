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
use Local;

use Carp;

use strict;
use vars qw($me $pc11_max_age $pc11_dup_age $pc23_dup_age %spotdup %wwvdup $last_hour %pings %rcmds %nodehops);

$me = undef;					# the channel id for this cluster
$pc11_max_age = 1*3600;			# the maximum age for an incoming 'real-time' pc11
$pc11_dup_age = 24*3600;		# the maximum time to keep the spot dup list for
$pc23_dup_age = 24*3600;		# the maximum time to keep the wwv dup list for
%spotdup = ();				    # the pc11 and 26 dup hash 
%wwvdup = ();				    # the pc23 and 27 dup hash 
$last_hour = time;				# last time I did an hourly periodic update
%pings = ();                    # outstanding ping requests outbound
%rcmds = ();                    # outstanding rcmd requests outbound
%nodehops = ();                 # node specific hop control


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
	
	# set unbuffered
	$self->send_now('B',"0");
	
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
				route($field[2], $line); # relay it on its way
			}
			return;
		}
		
		if ($pcno == 11 || $pcno == 26) { # dx spot
			
			# if this is a 'nodx' node then ignore it
			last SWITCH if grep $field[7] =~ /^$_/,  @DXProt::nodx_node;
			
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
			$spotter =~ s/-\d+$//o;	# strip off the ssid from the spotter
			
			# do some de-duping
			my $freq = $field[1] - 0;
			my $dupkey = "$freq$field[2]$d$text$spotter";
			if ($spotdup{$dupkey}) {
				dbg('chan', "Duplicate Spot ignored\n");
				return;
			}
			
			$spotdup{$dupkey} = $d;
			
			my $spot = Spot::add($freq, $field[2], $d, $text, $spotter, $field[7]);
			
			# local processing 
			my $r;
			eval {
				$r = Local::spot($self, $freq, $field[2], $d, $text, $spotter, $field[7]);
			};
#			dbg('local', "Local::spot1 error $@") if $@;
			return if $r;

			# send orf to the users
			if ($spot && $pcno == 11) {
				my $buf = Spot::formatb($field[1], $field[2], $d, $text, $spotter);
				broadcast_users("$buf\a\a", 'dx', $spot);
			}

			# DON'T be silly and send on PC26s!
			return if $pcno == 26;
			
			last SWITCH;
		}
		
		if ($pcno == 12) {		# announces
			
			if ($field[2] eq '*' || $field[2] eq $main::mycall) {
				
				# strip leading and trailing stuff
				my $text = unpad($field[3]);
				my $target;
				my $to = 'To ';
				my @list;
				
				if ($field[4] eq '*') {	# sysops
					$target = "SYSOP";
					@list = map { $_->priv >= 5 ? $_ : () } get_all_users();
				} elsif ($field[4] gt ' ') { # speciality list handling
					my ($name) = split /\./, $field[4]; 
					$target = "$name"; # put the rest in later (if bothered) 
				} 
				
				if ($field[6] eq '1') {
					$target = "WX"; 
					$to = '';
				}
				$target = "All" if !$target;
				
				if (@list > 0) {
					broadcast_list("$to$target de $field[1]: $text", 'ann', undef, @list);
				} else {
					broadcast_users("$target de $field[1]: $text", 'ann', undef);
				}
				Log('ann', $target, $field[1], $text);
				
				return if $field[2] eq $main::mycall; # it's routed to me
			} else {
				route($field[2], $line);
				return;			# only on a routed one
			}
			
			last SWITCH;
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
			last SWITCH if !$node; # ignore if havn't seen a PC19 for this one yet
			last SWITCH unless $node->isa('DXNode');
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
				$user->lastin($main::systime);
				$user->put;
			}
			
			# queue up any messages (look for privates only)
			DXMsg::queue_msg(1) if $self->state eq 'normal';     
			last SWITCH;
		}
		
		if ($pcno == 17) {		# remove a user
			
			my $ref = DXCluster->get_exact($field[1]);
			$ref->del() if $ref;
			last SWITCH;
		}
		
		if ($pcno == 18) {		# link request
			$self->send_local_config();
			$self->send(pc20());
			$self->state('init');	
			return;             # we don't pass these on
		}
		
		if ($pcno == 19) {		# incoming cluster list
			my $i;
			for ($i = 1; $i < $#field-1; $i += 4) {
				my $here = $field[$i];
				my $call = uc $field[$i+1];
				my $confmode = $field[$i+2] eq '*';
				my $ver = $field[$i+3];
				
				# now check the call over
				next if DXCluster->get_exact($call); # we already have this
				
				# check for sane parameters
				next if $ver < 5000; # only works with version 5 software
				next if length $call < 3; # min 3 letter callsigns
				DXNode->new($self, $call, $confmode, $here, $ver);
				
				# unbusy and stop and outgoing mail (ie if somehow we receive another PC19 without a disconnect)
				my $mref = DXMsg::get_busy($call);
				$mref->stop_msg($self) if $mref;
				
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
				$user->lastin($main::systime);
				$user->put;
			}
			
			# queue up any messages
			DXMsg::queue_msg(0) if $self->state eq 'normal';
			last SWITCH;
		}
		
		if ($pcno == 20) {		# send local configuration
			$self->send_local_config();
			$self->send(pc22());
			$self->state('normal');
			
			# queue mail
			DXMsg::queue_msg(0);
			return;
		}
		
		if ($pcno == 21) {		# delete a cluster from the list
			my $call = uc $field[1];
			if ($call ne $main::mycall) { # don't allow malicious buggers to disconnect me!
				my $ref = DXCluster->get_exact($call);
				$ref->del() if $ref;
			}
			last SWITCH;
		}
		
		if ($pcno == 22) {
			$self->state('normal');
			
			# queue mail
			DXMsg::queue_msg(0);
			return;
		}
		
		if ($pcno == 23 || $pcno == 27) { # WWV info
			# do some de-duping
			my $d = cltounix($field[1], sprintf("%02d18Z", $field[2]));
			my $sfi = unpad($field[3]);
			my $k = unpad($field[4]);
			my $i = unpad($field[5]);
			my $dupkey = "$d.$sfi$k$i";
			if ($wwvdup{$dupkey}) {
				dbg('chan', "Dup WWV Spot ignored\n");
				return;
			}
			if ($d > $main::systime + 900 || $field[2] < 0 || $field[2] > 23) {
				dbg('chan', "WWV Date ($field[1] $field[2]) out of range");
				return;
			}
			$wwvdup{$dupkey} = $d;
			$field[6] =~ s/-\d+$//o;            # remove spotter's ssid
		
			my $wwv = Geomag::update($d, $field[2], $sfi, $k, $i, @field[6..$#field]);

			my $r;
			eval {
				$r = Local::wwv($self, $field[1], $field[2], $sfi, $k, $i, @field[6..$#field]);
			};
#			dbg('local', "Local::wwv2 error $@") if $@;
			return if $r;

			# DON'T be silly and send on PC27s!
			return if $pcno == 27;

			# broadcast to the eager users
			broadcast_users("WWV de $field[7] <$field[2]>:   SFI=$sfi, K=$k, A=$i, $field[6]", 'wwv', $wwv );
			last SWITCH;
		}
		
		if ($pcno == 24) {		# set here status
			my $call = uc $field[1];
			my $ref = DXCluster->get_exact($call);
			$ref->here($field[2]) if $ref;
			last SWITCH;
		}
		
		if ($pcno == 25) {      # merge request
			unless ($field[1] eq $main::mycall) {
				dbg('chan', "merge request to $field[1] from $field[2] ignored");
				return;
			}

			Log('DXProt', "Merge request for $field[3] spots and $field[4] WWV from $field[1]");
			
			# spots
			if ($field[3] > 0) {
				my @in = reverse Spot::search(1, undef, undef, 0, $field[3]-1);
				my $in;
				foreach $in (@in) {
					$self->send(pc26(@{$in}[0..4], $in->[7]));
				}
			}

			# wwv
			if ($field[4] > 0) {
				my @in = reverse Geomag::search(0, $field[4], time, 1);
				my $in;
				foreach $in (@in) {
					$self->send(pc27(@{$in}));
				}
			}
			return;
		}
		
		if (($pcno >= 28 && $pcno <= 33) || $pcno == 40 || $pcno == 42 || $pcno == 49) { # mail/file handling
			DXMsg::process($self, $line);
			return;
		}
		
		if ($pcno == 34 || $pcno == 36) { # remote commands (incoming)
			if ($field[1] eq $main::mycall) {
				my $ref = DXUser->get_current($field[2]);
				Log('rcmd', 'in', $ref->{priv}, $field[2], $field[3]);
				unless ($field[3] =~ /rcmd/i) {    # not allowed to relay RCMDS!
					if ($ref->{priv}) {	# you have to have SOME privilege, the commands have further filtering
						$self->{remotecmd} = 1; # for the benefit of any command that needs to know
						my @in = (DXCommandmode::run_cmd($self, $field[3]));
						for (@in) {
							s/\s*$//og;
							$self->send(pc35($main::mycall, $field[2], "$main::mycall:$_"));
							Log('rcmd', 'out', $field[2], $_);
						}
						delete $self->{remotecmd};
					}
				} else {
					$self->send(pc35($main::mycall, $field[2], "$main::mycall:Tut tut tut...!"));
				}
			} else {
				route($field[1], $line);
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
				route($field[1], $line);
			}
			return;
		}
		
		if ($pcno == 37) {
			last SWITCH;
		}
		
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
		if ($pcno == 44) {
			last SWITCH;
		}
		if ($pcno == 45) {
			last SWITCH;
		}
		if ($pcno == 46) {
			last SWITCH;
		}
		if ($pcno == 47) {
			last SWITCH;
		}
		if ($pcno == 48) {
			last SWITCH;
		}
		
		if ($pcno == 50) {		# keep alive/user list
			my $ref = DXCluster->get_exact($field[1]);
			$ref->update_users($field[2]) if $ref;			
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
						my $r = shift @$ref;
						my $dxchan = DXChannel->get($r->{call});
						$dxchan->send($dxchan->msg('pingi', $field[2], atime($main::systime), $main::systime - $r->{t})) if $dxchan;
					}
				}
				
			} else {
				# route down an appropriate thingy
				route($field[1], $line);
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
	 
	if (!$self->{isolate}) {
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
	$mref->stop_msg($self) if $mref;
	
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
	broadcast_ak1a(pc21($call, 'Gone.'), $self);
	
	Log('DXProt', $call . " Disconnected");
	$ref->del() if $ref;
}

#
# some active measures
#

sub send_local_config
{
	my $self = shift;
	my $n;
	my @nodes;
	
	# send our nodes
	if ($self->{isolate}) {
		@nodes = (DXCluster->get_exact($main::mycall));
	} else {
		# create a list of all the nodes that are not connected to this connection
		@nodes = DXNode::get_all();
		@nodes = grep { $_->dxchan != $self } @nodes;
	}

	my @s = $me->pc19(@nodes);
	for (@s) {
		my $routeit = adjust_hops($self, $_);
		$self->send($routeit) if $routeit;
	}
	
	# get all the users connected on the above nodes and send them out
	foreach $n (@nodes) {
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
	my ($call, $line) = @_;
	my $cl = DXCluster->get_exact($call);
	if ($cl) {
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

# broadcast a message to all clusters [except those mentioned after buffer]
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
		
		next if $sort eq 'dx' && !$dxchan->{dx};
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
	my ($pcno) = @_;
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
	route($to, pc51($to, $main::mycall, 1));
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
	route($to, pc34($main::mycall, $to, $cmd));
	$rcmds{$to} = $r;
}
1;
__END__ 
