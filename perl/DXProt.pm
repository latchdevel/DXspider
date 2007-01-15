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
use DXProtVars;
use DXCommandmode;
use DXLog;
use Spot;
use DXProtout;
use DXDebug;
use Filter;
use Local;
use DXDb;
use AnnTalk;
use Geomag;
use WCY;
use BadWords;
use DXHash;
use Route;
use Route::Node;
use Script;
use RouteDB;
use DXProtHandle;

use strict;

use vars qw($VERSION $BRANCH);
use vars qw($pc11_max_age $pc23_max_age $last_pc50 $eph_restime $eph_info_restime $eph_pc34_restime
			$last_hour $last10 %eph  %pings %rcmds $ann_to_talk
			$pingint $obscount %pc19list $chatdupeage $chatimportfn
			$investigation_int $pc19_version $myprot_version
			%nodehops $baddx $badspotter $badnode $censorpc $rspfcheck
			$allowzero $decode_dk0wcy $send_opernam @checklist
			$eph_pc15_restime $pc92_update_period $last_pc92_update
		   );

($VERSION, $BRANCH) = dxver(q$Revision$);

$pc11_max_age = 1*3600;			# the maximum age for an incoming 'real-time' pc11
$pc23_max_age = 1*3600;			# the maximum age for an incoming 'real-time' pc23

$last_hour = time;				# last time I did an hourly periodic update
%rcmds = ();                    # outstanding rcmd requests outbound
%nodehops = ();                 # node specific hop control
%pc19list = ();					# list of outstanding PC19s that haven't had PC16s on them

$censorpc = 1;					# Do a BadWords::check on text fields and reject things
								# loads of 'bad things'
$baddx = new DXHash "baddx";
$badspotter = new DXHash "badspotter";
$badnode = new DXHash "badnode";
$last10 = $last_pc50 = time;
$ann_to_talk = 1;
$rspfcheck = 1;
$eph_restime = 180;
$eph_info_restime = 60*60;
$eph_pc15_restime = 6*60;
$eph_pc34_restime = 30;
$pingint = 5*60;
$obscount = 2;
$chatdupeage = 20 * 60 * 60;
$chatimportfn = "$main::root/chat_import";
$investigation_int = 12*60*60;	# time between checks to see if we can see this node
$pc19_version = 5466;			# the visible version no for outgoing PC19s generated from pc59
$pc92_update_period = 30*60;	# the period between PC92 C updates
$last_pc92_update = time + int rand(180);		# the last time a PC92 config update


@checklist = 
(
 [ qw(i c c m bp bc c) ],			# pc10
 [ qw(i f m d t m c c h) ],		# pc11
 [ qw(i c bm m bm bm p h) ],		# pc12
 [ qw(i c h) ],					# 
 [ qw(i c h) ],					# 
 [ qw(i c m h) ],					# 
 undef ,						# pc16 has to be validated manually
 [ qw(i c c h) ],					# pc17
 [ qw(i m n) ],					# pc18
 undef ,						# pc19 has to be validated manually
 undef ,						# pc20 no validation
 [ qw(i c m h) ],					# pc21
 undef ,						# pc22 no validation
 [ qw(i d n n n n m c c h) ],		# pc23
 [ qw(i c p h) ],					# pc24
 [ qw(i c c n n) ],				# pc25
 [ qw(i f m d t m c c bc) ],		# pc26
 [ qw(i d n n n n m c c bc) ],	# pc27
 [ qw(i c c m c d t p m bp n p bp bc) ], # pc28
 [ qw(i c c n m) ],				# pc29
 [ qw(i c c n) ],					# pc30
 [ qw(i c c n) ],					# pc31
 [ qw(i c c n) ],					# pc32
 [ qw(i c c n) ],					# pc33
 [ qw(i c c m) ],					# pc34
 [ qw(i c c m) ],					# pc35
 [ qw(i c c m) ],					# pc36
 [ qw(i c c n m) ],				# pc37
 undef,							# pc38 not interested
 [ qw(i c m) ],					# pc39
 [ qw(i c c m p n) ],				# pc40
 [ qw(i c n m h) ],				# pc41
 [ qw(i c c n) ],					# pc42
 undef,							# pc43 don't handle it
 [ qw(i c c n m m c) ],			# pc44
 [ qw(i c c n m) ],				# pc45
 [ qw(i c c n) ],					# pc46
 undef,							# pc47
 undef,							# pc48
 [ qw(i c m h) ],					# pc49
 [ qw(i c n h) ],					# pc50
 [ qw(i c c n) ],					# pc51
 undef,
 undef,
 undef,
 undef,
 undef,
 undef,
 undef,
 undef,
 undef,							# pc60
 undef,
 undef,
 undef,
 undef,
 undef,
 undef,
 undef,
 undef,
 undef,
 undef,							# pc70
 undef,
 undef,
 [ qw(i d n n n n n n m m m c c h) ],	# pc73
 undef,
 undef,
 undef,
 undef,
 undef,
 undef,
 undef,							# pc80
 undef,
 undef,
 undef,
 [ qw(i c c c m) ],				# pc84
 [ qw(i c c c m) ],				# pc85
 undef,
 undef,
 undef,
 undef,
 [ qw(i c n) ],					# pc90
);

# use the entry in the check list to check the field list presented
# return OK if line NOT in check list (for now)
sub check
{
	my $n = shift;
	$n -= 10;
	return 0 if $n < 0 || $n > @checklist; 
	my $ref = $checklist[$n];
	return 0 unless ref $ref;
	
	my $i;
	for ($i = 1; $i < @$ref; $i++) {
		my ($blank, $act) = $$ref[$i] =~ /^(b?)(\w)$/;
		return 0 unless $act;
		next if $blank && $_[$i] =~ /^[ \*]$/;
		if ($act eq 'c') {
			return $i unless is_callsign($_[$i]);
		} elsif ($act eq 'i') {			
			;					# do nothing
		} elsif ($act eq 'm') {
			return $i unless is_pctext($_[$i]);
		} elsif ($act eq 'p') {
			return $i unless is_pcflag($_[$i]);
		} elsif ($act eq 'f') {
			return $i unless is_freq($_[$i]);
		} elsif ($act eq 'n') {
			return $i unless $_[$i] =~ /^[\d ]+$/;
		} elsif ($act eq 'h') {
			return $i unless $_[$i] =~ /^H\d\d?$/;
		} elsif ($act eq 'd') {
			return $i unless $_[$i] =~ /^\s*\d+-\w\w\w-[12][90]\d\d$/;
		} elsif ($act eq 't') {
			return $i unless $_[$i] =~ /^[012]\d[012345]\dZ$/;
		} 
	}
	return 0;
}

sub init
{
	do "$main::data/hop_table.pl" if -e "$main::data/hop_table.pl";
	confess $@ if $@;

	my $user = DXUser->get($main::mycall);
	die "User $main::mycall not setup or disappeared RTFM" unless $user;
	
	$myprot_version += $main::version*100;
	$main::me = DXProt->new($main::mycall, 0, $user); 
	$main::me->{here} = 1;
	$main::me->{state} = "indifferent";
	$main::me->{sort} = 'S';    # S for spider
	$main::me->{priv} = 9;
	$main::me->{metric} = 0;
	$main::me->{pingave} = 0;
	$main::me->{registered} = 1;
	$main::me->{version} = $main::version;
	$main::me->{build} = $main::build;
	$main::me->{do_pc92} = 1;
	$main::me->{via_pc92} = 1;
}

#
# obtain a new connection this is derived from dxchannel
#

sub new 
{
	my $self = DXChannel::alloc(@_);

	# add this node to the table, the values get filled in later
	my $pkg = shift;
	my $call = shift;
	$main::routeroot->add($call, '5000', Route::here(1)) if $call ne $main::mycall;

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

	# log it
	my $host = $self->{conn}->{peerhost};
	$host ||= "AGW Port #$self->{conn}->{agwport}" if exists $self->{conn}->{agwport};
	$host ||= "unknown";

	Log('DXProt', "$call connected from $host");
	
	# remember type of connection
	$self->{consort} = $line;
	$self->{outbound} = $sort eq 'O';
	my $priv = $user->priv;
	$priv = $user->priv(1) unless $priv;
	$self->{priv} = $priv;     # other clusters can always be 'normal' users
	$self->{lang} = $user->lang || 'en';
	$self->{isolate} = $user->{isolate};
	$self->{consort} = $line;	# save the connection type
	$self->{here} = 1;
	$self->{width} = 80;

	# sort out registration
	$self->{registered} = 1;

	# get the output filters
	$self->{spotsfilter} = Filter::read_in('spots', $call, 0) || Filter::read_in('spots', 'node_default', 0);
	$self->{wwvfilter} = Filter::read_in('wwv', $call, 0) || Filter::read_in('wwv', 'node_default', 0);
	$self->{wcyfilter} = Filter::read_in('wcy', $call, 0) || Filter::read_in('wcy', 'node_default', 0);
	$self->{annfilter} = Filter::read_in('ann', $call, 0) || Filter::read_in('ann', 'node_default', 0) ;
	$self->{routefilter} = Filter::read_in('route', $call, 0) || Filter::read_in('route', 'node_default', 0) unless $self->{isolate} ;


	# get the INPUT filters (these only pertain to Clusters)
	$self->{inspotsfilter} = Filter::read_in('spots', $call, 1) || Filter::read_in('spots', 'node_default', 1);
	$self->{inwwvfilter} = Filter::read_in('wwv', $call, 1) || Filter::read_in('wwv', 'node_default', 1);
	$self->{inwcyfilter} = Filter::read_in('wcy', $call, 1) || Filter::read_in('wcy', 'node_default', 1);
	$self->{inannfilter} = Filter::read_in('ann', $call, 1) || Filter::read_in('ann', 'node_default', 1);
	$self->{inroutefilter} = Filter::read_in('route', $call, 1) || Filter::read_in('route', 'node_default', 1) unless $self->{isolate};
	
	# set unbuffered and no echo
	$self->send_now('B',"0");
	$self->send_now('E',"0");
	$self->conn->echo(0) if $self->conn->can('echo');
	
	# ping neighbour node stuff
	my $ping = $user->pingint;
	$ping = $pingint unless defined $ping;
	$self->{pingint} = $ping;
	$self->{nopings} = $user->nopings || $obscount;
	$self->{pingtime} = [ ];
	$self->{pingave} = 999;
	$self->{metric} ||= 100;
	$self->{lastping} = $main::systime;
	
	# send initialisation string
	unless ($self->{outbound}) {
		$self->sendinit;
	}
	
	$self->state('init');
	$self->{pc50_t} = $main::systime;

	# send info to all logged in thingies
	$self->tell_login('loginn');

	# run a script send the output to the debug file
	my $script = new Script(lc $call) || new Script('node_default');
	$script->run($self) if $script;
}

#
# send outgoing 'challenge'
#

sub sendinit
{
	my $self = shift;
	$self->send(pc18());
}

#
# This is the normal pcxx despatcher
#
sub normal
{
	my ($self, $line) = @_;

	if ($line =~ '^<\w+\s' && $main::do_xml) {
		DXXml::normal($self, $line);
		return;
	}

	my @field = split /\^/, $line;
	return unless @field;
	
	pop @field if $field[-1] eq '~';
	
#	print join(',', @field), "\n";
						
	
	# process PC frames, this will fail unless the frame starts PCnn
	my ($pcno) = $field[0] =~ /^PC(\d\d)/; # just get the number
	unless (defined $pcno && $pcno >= 10 && $pcno <= 99) {
		dbg("PCPROT: unknown protocol") if isdbg('chanerr');
		return;
	}

	# check for and dump bad protocol messages
	my $n = check($pcno, @field);
	if ($n) {
		dbg("PCPROT: bad field $n, dumped (" . parray($checklist[$pcno-10]) . ")") if isdbg('chanerr');
		return;
	}

	# modify the hop count here
	if (my ($hops, $trail) = $line =~ /\^H(\d+)(\^?\~?)?$/) {
		$trail ||= '';
		$hops--;
		return if $hops < 0;
		$line =~ s/\^H(\d+)(\^?\~?)?$/sprintf('^H%d%s', $hops, $trail)/e;
		$field[-1] = "H$hops";
	}

	# send it out for processing
	my $origin = $self->{call};
	no strict 'subs';
	my $sub = "handle_$pcno";

	if ($self->can($sub)) {
		$self->$sub($pcno, $line, $origin, @field);
	} else {
		$self->handle_default($pcno, $line, $origin, @field);
	}
}

#
# This is called from inside the main cluster processing loop and is used
# for despatching commands that are doing some long processing job
#
sub process
{
	my $t = time;
	my @dxchan = DXChannel::get_all();
	my $dxchan;
	my $pc50s;
	
	# send out a pc50 on EVERY channel all at once
	if ($t >= $last_pc50 + $DXProt::pc50_interval) {
		$pc50s = pc50($main::me, scalar DXChannel::get_all_users);
		eph_dup($pc50s);
		$last_pc50 = $t;
	}

	foreach $dxchan (@dxchan) {
		next unless $dxchan->is_node;
		next if $dxchan->handle_xml;
		next if $dxchan == $main::me;

		# send the pc50
		$dxchan->send($pc50s) if $pc50s;
		
		# send a ping out on this channel
		if ($dxchan->{pingint} && $t >= $dxchan->{pingint} + $dxchan->{lastping}) {
			if ($dxchan->{nopings} <= 0) {
				$dxchan->disconnect;
			} else {
				DXXml::Ping::add($main::me, $dxchan->call);
				$dxchan->{nopings} -= 1;
				$dxchan->{lastping} = $t;
				$dxchan->{lastping} += $dxchan->{pingint} / 2 unless @{$dxchan->{pingtime}};
			}
		}
	}

	Investigate::process();

	# every ten seconds
	if ($t - $last10 >= 10) {	
		# clean out ephemera 

		eph_clean();
		import_chat();

		if ($main::systime >= $last_pc92_update + $pc92_update_period) {
			dbg("ROUTE: sending pc92 update") if isdbg('route');
			send_pc92_update();
			time_out_pc92_routes();
			$last_pc92_update = $main::systime + int rand(180);
		}
		
		$last10 = $t;
	}
	
	if ($main::systime - 3600 > $last_hour) {
		$last_hour = $main::systime;
	}
}

#
# finish up a pc context
#

#
# some active measures
#


sub send_dx_spot
{
	my $self = shift;
	my $line = shift;
	my @dxchan = DXChannel::get_all();
	my $dxchan;
	
	# send it if it isn't the except list and isn't isolated and still has a hop count
	# taking into account filtering and so on
	foreach $dxchan (@dxchan) {
		next if $dxchan == $main::me;
		next if $dxchan == $self && $self->is_node;
		$dxchan->dx_spot($line, $self->{isolate}, @_, $self->{call});
	}
}

sub dx_spot
{
	my $self = shift;
	my $line = shift;
	my $isolate = shift;
	my ($filter, $hops);

	if ($self->{spotsfilter}) {
		($filter, $hops) = $self->{spotsfilter}->it(@_);
		return unless $filter;
	}
	send_prot_line($self, $filter, $hops, $isolate, $line);
}

sub send_prot_line
{
	my ($self, $filter, $hops, $isolate, $line) = @_;
	my $routeit;


	if ($hops) {
		$routeit = $line;
		$routeit =~ s/\^H\d+\^\~$/\^H$hops\^\~/;
	} else {
		$routeit = adjust_hops($self, $line);  # adjust its hop count by node name
		return unless $routeit;
	}
	if ($filter) {
		$self->send($routeit);
	} else {
		$self->send($routeit) unless $self->{isolate} || $isolate;
	}
}


sub send_wwv_spot
{
	my $self = shift;
	my $line = shift;
	my @dxchan = DXChannel::get_all();
	my $dxchan;
	my @dxcc = ((Prefix::cty_data($_[6]))[0..2], (Prefix::cty_data($_[7]))[0..2]);

	# send it if it isn't the except list and isn't isolated and still has a hop count
	# taking into account filtering and so on
	foreach $dxchan (@dxchan) {
		next if $dxchan == $main::me;
		next if $dxchan == $self && $self->is_node;
		my $routeit;
		my ($filter, $hops);

		$dxchan->wwv($line, $self->{isolate}, @_, $self->{call}, @dxcc);
	}
}

sub wwv
{
	my $self = shift;
	my $line = shift;
	my $isolate = shift;
	my ($filter, $hops);
	
	if ($self->{wwvfilter}) {
		($filter, $hops) = $self->{wwvfilter}->it(@_[7..$#_]);
		return unless $filter;
	}
	send_prot_line($self, $filter, $hops, $isolate, $line)
}

sub send_wcy_spot
{
	my $self = shift;
	my $line = shift;
	my @dxchan = DXChannel::get_all();
	my $dxchan;
	my @dxcc = ((Prefix::cty_data($_[10]))[0..2], (Prefix::cty_data($_[11]))[0..2]);
	
	# send it if it isn't the except list and isn't isolated and still has a hop count
	# taking into account filtering and so on
	foreach $dxchan (@dxchan) {
		next if $dxchan == $main::me;
		next if $dxchan == $self;

		$dxchan->wcy($line, $self->{isolate}, @_, $self->{call}, @dxcc);
	}
}

sub wcy
{
	my $self = shift;
	my $line = shift;
	my $isolate = shift;
	my ($filter, $hops);

	if ($self->{wcyfilter}) {
		($filter, $hops) = $self->{wcyfilter}->it(@_);
		return unless $filter;
	}
	send_prot_line($self, $filter, $hops, $isolate, $line) if $self->is_clx || $self->is_spider || $self->is_dxnet;
}

# send an announce
sub send_announce
{
	my $self = shift;
	my $line = shift;
	my @dxchan = DXChannel::get_all();
	my $dxchan;
	my $target;
	my $to = 'To ';
	my $text = unpad($_[2]);
				
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
	$target = "ALL" if !$target;


	# obtain country codes etc 
	my @a = Prefix::cty_data($_[0]);
	my @b = Prefix::cty_data($_[4]);
	if ($self->{inannfilter}) {
		my ($filter, $hops) = 
			$self->{inannfilter}->it(@_, $self->{call}, 
									 @a[0..2],
									 @b[0..2], $a[3], $b[3]);
		unless ($filter) {
			dbg("PCPROT: Rejected by input announce filter") if isdbg('chanerr');
			return;
		}
	}

	if (AnnTalk::dup($_[0], $_[1], $_[2])) {
		dbg("PCPROT: Duplicate Announce ignored") if isdbg('chanerr');
		return;
	}

	Log('ann', $target, $_[0], $text);

	# send it if it isn't the except list and isn't isolated and still has a hop count
	# taking into account filtering and so on
	foreach $dxchan (@dxchan) {
		next if $dxchan == $main::me;
		next if $dxchan == $self && $self->is_node;
		$dxchan->announce($line, $self->{isolate}, $to, $target, $text, @_, $self->{call},
						  @a[0..2], @b[0..2]);
	}
}

my $msgid = 0;

sub nextchatmsgid
{
	$msgid++;
	$msgid = 1 if $msgid > 999;
	return $msgid;
}

# send a chat line
sub send_chat
{
	my $self = shift;
	my $line = shift;
	my @dxchan = DXChannel::get_all();
	my $dxchan;
	my $target = $_[3];
	my $text = unpad($_[2]);
	my $ak1a_line;
				
	# munge the group and recast the line if required
	if ($target =~ s/\.LST$//) {
		$ak1a_line = $line;
	}
	
	# obtain country codes etc 
	my @a = Prefix::cty_data($_[0]);
	my @b = Prefix::cty_data($_[4]);
	if ($self->{inannfilter}) {
		my ($filter, $hops) = 
			$self->{inannfilter}->it(@_, $self->{call}, 
									 @a[0..2],
									 @b[0..2], $a[3], $b[3]);
		unless ($filter) {
			dbg("PCPROT: Rejected by input announce filter") if isdbg('chanerr');
			return;
		}
	}

	if (AnnTalk::dup($_[0], $_[1], $_[2], $chatdupeage)) {
		dbg("PCPROT: Duplicate Announce ignored") if isdbg('chanerr');
		return;
	}


	Log('chat', $target, $_[0], $text);

	# send it if it isn't the except list and isn't isolated and still has a hop count
	# taking into account filtering and so on
	foreach $dxchan (@dxchan) {
		my $is_ak1a = $dxchan->is_ak1a;
		
		if ($dxchan->is_node) {
			next if $dxchan == $main::me;
			next if $dxchan == $self;
			next unless $dxchan->is_spider || $is_ak1a;
			next if $target eq 'LOCAL';
			if (!$ak1a_line && $is_ak1a) {
				$ak1a_line = DXProt::pc12($_[0], $text, $_[1], "$target.LST");
			}
		}
		
		$dxchan->chat($is_ak1a ? $ak1a_line : $line, $self->{isolate}, $target, $_[1], 
					  $text, @_, $self->{call}, @a[0..2], @b[0..2]);
	}
}

sub announce
{
	my $self = shift;
	my $line = shift;
	my $isolate = shift;
	my $to = shift;
	my $target = shift;
	my $text = shift;
	my ($filter, $hops);

	if ($self->{annfilter}) {
		($filter, $hops) = $self->{annfilter}->it(@_);
		return unless $filter;
	}
	send_prot_line($self, $filter, $hops, $isolate, $line) unless $_[1] eq $main::mycall;
}

sub chat
{
	goto &announce;
}


sub send_local_config
{
	my $self = shift;

	dbg('DXProt::send_local_config') if isdbg('trace');

	# send our nodes
	if ($self->{do_pc92}) { 
		$self->send_pc92_config;
	} else {
		my $node;
		my @nodes;
		my @localnodes;
		my @remotenodes;

		if ($self->{isolate}) {
			@localnodes = ( $main::routeroot );
			$self->send_route($main::mycall, \&pc19, 1, $main::routeroot);
		} else {
			# create a list of all the nodes that are not connected to this connection
			# and are not themselves isolated, this to make sure that isolated nodes
			# don't appear outside of this node

			# send locally connected nodes
			my @dxchan = grep { $_->call ne $main::mycall && $_ != $self && !$_->{isolate} } DXChannel::get_all_nodes();
			@localnodes = map { my $r = Route::Node::get($_->{call}); $r ? $r : () } @dxchan if @dxchan;
			$self->send_route($main::mycall, \&pc19, scalar(@localnodes)+1, $main::routeroot, @localnodes);

			my $node;
			my @rawintcalls = map { $_->nodes } @localnodes if @localnodes;
			my @intcalls;
			for $node (@rawintcalls) {
				push @intcalls, $node unless grep $node eq $_, @intcalls; 
			}
			my $ref = Route::Node::get($self->{call});
			my @rnodes = $ref->nodes;
			for $node (@intcalls) {
				push @remotenodes, Route::Node::get($node) unless grep $node eq $_, @rnodes, @remotenodes;
			}
			$self->send_route($main::mycall, \&pc19, scalar(@remotenodes), @remotenodes);
		}
	
		# get all the users connected on the above nodes and send them out
		foreach $node ($main::routeroot, @localnodes, @remotenodes) {
			if ($node) {
				my @rout = map {my $r = Route::User::get($_); $r ? ($r) : ()} $node->users;
				$self->send_route($main::mycall, \&pc16, 1, $node, @rout) if @rout && $self->user->wantsendpc16;
			} else {
				dbg("sent a null value") if isdbg('chanerr');
			}
		}
	}
}

sub gen_pc92_update
{
	my $self = shift;
	my $with_pc92_nodes = shift;
	my $node;
	my @lines;
	
	dbg('DXProt::gen_pc92_update') if isdbg('trace');

	# send 'my' configuration for all users and pc92 capable nodes
	my @dxchan = grep { $_->call ne $main::mycall && $_ != $self && !$_->{isolate} } DXChannel::get_all();
	my @localnodes = map { my $r = Route::get($_->{call}); $r ? $r : () } @dxchan;
	push @lines, pc92c($main::routeroot, @localnodes);


	if ($with_pc92_nodes) {
		# send out the configuration of all the directly connected PC92 nodes with current configuration
		# but with the dates that the last config came in with.
		@dxchan = grep { $_->call ne $main::mycall && $_ != $self && !$_->{isolate} && $_->{do_pc92} } DXChannel::get_all_nodes();
		@localnodes = map { my $r = Route::Node::get($_->{call}); $r ? $r : () } @dxchan;
		foreach $node (@localnodes) {
			if ($node && $node->lastid->{92}) {
				my @rout = map {my $r = Route::get($_); $r ? ($r) : ()} $node->nodes, $node->users;
				push @lines, gen_pc92_with_time($node->call, 'C', $node->lastid->{92}, @rout);
			}
		}
	}
	
	# send the configuration of all the directly connected 'external' nodes that don't handle PC92
	# out with the 'external' marker on the first node.
	@dxchan = grep { $_->call ne $main::mycall && $_ != $self && !$_->{isolate} && !$_->{do_pc92} } DXChannel::get_all_nodes();
	@localnodes = map { my $r = Route::Node::get($_->{call}); $r ? $r : () } @dxchan;
	foreach $node (@localnodes) {
		if ($node) {
			my @rout = map {my $r = Route::User::get($_); $r ? ($r) : ()} $node->users;
			push @lines, pc92c($node, @rout);
		} 
	}
	return @lines;
}


sub send_pc92_config
{
	my $self = shift;

	dbg('DXProt::send_pc92_config') if isdbg('trace');

	my @out = $self->gen_pc92_update(1);
	
	# send the complete config out on this interface
	for (@out) {
		$self->send($_);
	}
} 

sub send_pc92_update
{
	my @out = $main::me->gen_pc92_update(0);
	
	# broadcast the lines to all PC92 nodes
	for (@out) {
		$main::me->broadcast_route_pc9x($main::mycall, undef, $_, 0);
	}
} 

sub time_out_pc92_routes
{
	my @nodes = grep {$_->call ne $main::mycall && ($_->do_pc92 || $_->via_pc92)} Route::Node::get_all();
	my @rdel;
	foreach my $n (@nodes) {
		my $o = $n->dec_obs;
		if ($o <= 0) {
			if (my $dxchan = DXChannel::get($n->call)) {
				dbg("ROUTE: disconnecting local pc92 $dxchan->{call} on obscount") if isdbg('route');
				$dxchan->disconnect;
				next;
			}
			my @parents = map {Route::Node::get($_)} $n->parents;
			for (@parents) {
				if ($_) {
					dbg("ROUTE: deleting pc92 $_->{call} from $n->{call} on obscount") if isdbg('route');
					push @rdel, $n->del($_);
				}
			}
		} else {
			dbg("ROUTE: obscount on $n->{call} now $o") if isdbg('route');
		}
	}
	for (@rdel) {
		$main::me->route_pc21($main::mycall, undef, $_) if $_;
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

	if (ref $self && $call eq $self->{call}) {
		dbg("PCPROT: Trying to route back to source, dropped") if isdbg('chanerr');
		return;
	}

	# always send it down the local interface if available
	my $dxchan = DXChannel::get($call);
	if ($dxchan) {
		dbg("route: $call -> $dxchan->{call} direct" ) if isdbg('route');
	} else {
		my $cl = Route::get($call);
		$dxchan = $cl->dxchan if $cl;
		if (ref $dxchan) {
			if (ref $self && $dxchan eq $self) {
				dbg("PCPROT: Trying to route back to source, dropped") if isdbg('chanerr');
				return;
			}
			dbg("route: $call -> $dxchan->{call} using normal route" ) if isdbg('route');
		}
	}

	# try the backstop method
	unless ($dxchan) {
		my $rcall = RouteDB::get($call);
		if ($rcall) {
			if ($self && $rcall eq $self->{call}) {
				dbg("PCPROT: Trying to route back to source, dropped") if isdbg('chanerr');
				return;
			}
			$dxchan = DXChannel::get($rcall);
			dbg("route: $call -> $rcall using RouteDB" ) if isdbg('route') && $dxchan;
		}
	}

	if ($dxchan) {
		my $routeit = adjust_hops($dxchan, $line);   # adjust its hop count by node name
		if ($routeit) {
			$dxchan->send($routeit) unless $dxchan == $main::me;
		}
	} else {
		dbg("PCPROT: No route available, dropped") if isdbg('chanerr');
	}
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
	
	if (($hops) = $s =~ /\^H(\d+)\^?~?$/o) {
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
	return ();
}

sub process_rcmd
{
	my ($self, $tonode, $fromnode, $user, $cmd) = @_;
	if ($tonode eq $main::mycall) {
		my $ref = DXUser->get_current($fromnode);
		my $cref = Route::Node::get($fromnode);
		Log('rcmd', 'in', $ref->{priv}, $fromnode, $cmd);
		if ($cmd !~ /^\s*rcmd/i && $cref && $ref && $cref->call eq $ref->homenode) { # not allowed to relay RCMDS!
			if ($ref->{priv}) {		# you have to have SOME privilege, the commands have further filtering
				$self->{remotecmd} = 1; # for the benefit of any command that needs to know
				my $oldpriv = $self->{priv};
				$self->{priv} = $ref->{priv}; # assume the user's privilege level
				my @in = (DXCommandmode::run_cmd($self, $cmd));
				$self->{priv} = $oldpriv;
				$self->send_rcmd_reply($main::mycall, $fromnode, $user, @in);
				delete $self->{remotecmd};
			} else {
				$self->send_rcmd_reply($main::mycall, $fromnode, $user, "sorry...!");
			}
		} else {
			$self->send_rcmd_reply($main::mycall, $fromnode, $user, "your attempt is logged, Tut tut tut...!");
		}
	} else {
		my $ref = DXUser->get_current($tonode);
		if ($ref && $ref->is_clx) {
			$self->route($tonode, pc84($fromnode, $tonode, $user, $cmd));
		} else {
			$self->route($tonode, pc34($fromnode, $tonode, $cmd));
		}
	}
}

sub process_rcmd_reply
{
	my ($self, $tonode, $fromnode, $user, $line) = @_;
	if ($tonode eq $main::mycall) {
		my $s = $rcmds{$fromnode};
		if ($s) {
			my $dxchan = DXChannel::get($s->{call});
			my $ref = $user eq $tonode ? $dxchan : (DXChannel::get($user) || $dxchan);
			$ref->send($line) if $ref;
			delete $rcmds{$fromnode} if !$dxchan;
		} else {
			# send unsolicited ones to the sysop
			my $dxchan = DXChannel::get($main::myalias);
			$dxchan->send($line) if $dxchan;
		}
	} else {
		my $ref = DXUser->get_current($tonode);
		if ($ref && $ref->is_clx) {
			$self->route($tonode, pc85($fromnode, $tonode, $user, $line));
		} else {
			$self->route($tonode, pc35($fromnode, $tonode, $line));
		}
	}
}

sub send_rcmd_reply
{
	my $self = shift;
	my $tonode = shift;
	my $fromnode = shift;
	my $user = shift;
	while (@_) {
		my $line = shift;
		$line =~ s/\s*$//;
		Log('rcmd', 'out', $fromnode, $line);
		if ($self->is_clx) {
			$self->send(pc85($main::mycall, $fromnode, $user, "$main::mycall:$line"));
		} else {
			$self->send(pc35($main::mycall, $fromnode, "$main::mycall:$line"));
		}
	}
}

# add a rcmd request to the rcmd queues
sub addrcmd
{
	my ($self, $to, $cmd) = @_;

	my $r = {};
	$r->{call} = $self->{call};
	$r->{t} = $main::systime;
	$r->{cmd} = $cmd;
	$rcmds{$to} = $r;
	
	my $ref = Route::Node::get($to);
	my $dxchan = $ref->dxchan;
	if ($dxchan && $dxchan->is_clx) {
		route(undef, $to, pc84($main::mycall, $to, $self->{call}, $cmd));
	} else {
		route(undef, $to, pc34($main::mycall, $to, $cmd));
	}
}

sub disconnect
{
	my $self = shift;
	my $pc39flag = shift;
	my $call = $self->call;

	return if $self->{disconnecting}++;
	
	unless ($pc39flag && $pc39flag == 1) {
		$self->send_now("D", DXProt::pc39($main::mycall, $self->msg('disc1', "System Op")));
	}

	# get rid of any PC16/17/19
	eph_del_regex("^PC1[679]*$call");

	# do routing stuff, remove me from routing table
	my $node = Route::Node::get($call);
	my @rout;
	if ($node) {
		@rout = $node->del($main::routeroot);
		
		# and all my ephemera as well
		for (@rout) {
			my $c = $_->call;
			eph_del_regex("^PC1[679].*$c");
		}
	}

	RouteDB::delete_interface($call);
	
	# unbusy and stop and outgoing mail
	my $mref = DXMsg::get_busy($call);
	$mref->stop_msg($call) if $mref;
	
	# broadcast to all other nodes that all the nodes connected to via me are gone
	unless ($pc39flag && $pc39flag == 2)  {
		$self->route_pc21($main::mycall, undef, @rout) if @rout;
		$self->route_pc92d($main::mycall, undef, $main::routeroot, $node) if $node;
	}

	# remove outstanding pings
	delete $pings{$call};
	
	# I was the last node visited
    $self->user->node($main::mycall);

	# send info to all logged in thingies
	$self->tell_login('logoutn');

	Log('DXProt', $call . " Disconnected");

	$self->SUPER::disconnect;
}


# 
# send a talk message to this thingy
#
sub talk
{
	my ($self, $from, $to, $via, $line, $origin) = @_;
	
	$line =~ s/\^/\\5E/g;			# remove any ^ characters
	$self->send(DXProt::pc10($from, $to, $via, $line, $origin));
	Log('talk', $to, $from, $via?$via:$self->call, $line) unless $origin && $origin ne $main::mycall;
}

# send it if it isn't the except list and isn't isolated and still has a hop count
# taking into account filtering and so on

sub send_route
{
	my $self = shift;
	my $origin = shift;
	my $generate = shift;
	my $no = shift;     # the no of things to filter on 
	my $routeit;
	my ($filter, $hops);
	my @rin;
	
	for (; @_ && $no; $no--) {
		my $r = shift;
		
		if (!$self->{isolate} && $self->{routefilter}) {
			$filter = undef;
			if ($r) {
				($filter, $hops) = $self->{routefilter}->it($self->{call}, $self->{dxcc}, $self->{itu}, $self->{cq}, $r->call, $r->dxcc, $r->itu, $r->cq, $self->{state}, $r->{state});
				if ($filter) {
					push @rin, $r;
				} else {
					dbg("DXPROT: $self->{call}/" . $r->call . " rejected by output filter") if isdbg('chanerr');
				}
			} else {
				dbg("was sent a null value") if isdbg('chanerr');
			}
		} else {
			push @rin, $r unless $self->{isolate} && $r->call ne $main::mycall;
		}
	}
	if (@rin) {
		foreach my $line (&$generate(@rin, @_)) {
			if ($hops) {
				$routeit = $line;
				$routeit =~ s/\^H\d+\^\~$/\^H$hops\^\~/;
			} else {
				$routeit = adjust_hops($self, $line);  # adjust its hop count by node name
				next unless $routeit;
			}
			
			$self->send($routeit);
		}
	}
}

sub broadcast_route
{
	my $self = shift;
	my $origin = shift;
	my $generate = shift;
	my $line = shift;
	my @dxchan = DXChannel::get_all_nodes();
	my $dxchan;

	if ($line) {
		$line =~ /\^H(\d+)\^?\~?$/;
		return unless $1 > 0;
	}
	unless ($self->{isolate}) {
		foreach $dxchan (@dxchan) {
			next if $dxchan == $self;
			next if $dxchan == $main::me;
			next unless $dxchan->isa('DXProt');
			next if $dxchan->{do_pc92};
			next if ($generate == \&pc16 || $generate==\&pc17) && !$dxchan->user->wantsendpc16;
 
			$dxchan->send_route($origin, $generate, @_);
		}
	}
}

# this is only used for next door nodes on init
sub send_route_pc92
{
	my $self = shift;

	return unless $self->{do_pc92};
	
	my $origin = shift;
	my $generate = shift;
	my $no = shift;     # the no of things to filter on 
	my $line;

	$line = &$generate(@_);
	$self->send($line);
}

sub broadcast_route_pc9x
{
	my $self = shift;
	my $origin = shift;
	my $generate = shift;
	my $line = shift;
	my $no = shift;
	my @dxchan = DXChannel::get_all_nodes();
	my $dxchan;

	if ($origin eq $main::mycall && $generate && !$line) {
		$line = &$generate(@_);
	} 

	$line =~ /\^H(\d+)\^\~?$/;
	unless ($1 > 0 && $self->{isolate}) {
		foreach $dxchan (@dxchan) {
			next if $dxchan == $self || $dxchan == $main::me;
			next if $origin eq $dxchan->{call};	# don't route some from this call back again.
			next unless $dxchan->{do_pc92};
			next unless $dxchan->isa('DXProt');

			$dxchan->send($line);
		}
	}
}

sub route_pc16
{
	my $self = shift;
	return unless $self->user->wantpc16;
	my $origin = shift;
	my $line = shift;
	broadcast_route($self, $origin, \&pc16, $line, 1, @_);
}

sub route_pc17
{
	my $self = shift;
	return unless $self->user->wantpc16;
	my $origin = shift;
	my $line = shift;
	broadcast_route($self, $origin, \&pc17, $line, 1, @_);
}

sub route_pc19
{
	my $self = shift;
	my $origin = shift;
	my $line = shift;
	broadcast_route($self, $origin, \&pc19, $line, scalar @_, @_);
}

sub route_pc21
{
	my $self = shift;
	my $origin = shift;
	my $line = shift;
	broadcast_route($self, $origin, \&pc21, $line, scalar @_, @_);
}

sub route_pc24
{
	my $self = shift;
	my $origin = shift;
	my $line = shift;
	broadcast_route($self, $origin, \&pc24, $line, 1, @_);
}

sub route_pc41
{
	my $self = shift;
	my $origin = shift;
	my $line = shift;
	broadcast_route($self, $origin, \&pc41, $line, 1, @_);
}

sub route_pc50
{
	my $self = shift;
	my $origin = shift;
	my $line = shift;
	broadcast_route($self, $origin, \&pc50, $line, 1, @_);
}

sub route_pc92c
{
	my $self = shift;
	my $origin = shift;
	my $line = shift;
	broadcast_route_pc9x($self, $origin, \&pc92c, $line, 1, @_);
}

sub route_pc92a
{
	my $self = shift;
	my $origin = shift;
	my $line = shift;
	broadcast_route_pc9x($self, $origin, \&pc92a, $line, 1, @_);
}

sub route_pc92d
{
	my $self = shift;
	my $origin = shift;
	my $line = shift;
	broadcast_route_pc9x($self, $origin, \&pc92d, $line, 1, @_);
}

sub in_filter_route
{
	my $self = shift;
	my $r = shift;
	my ($filter, $hops) = (1, 1);
	
	if ($self->{inroutefilter}) {
		($filter, $hops) = $self->{inroutefilter}->it($self->{call}, $self->{dxcc}, $self->{itu}, $self->{cq}, $r->call, $r->dxcc, $r->itu, $r->cq, $self->state, $r->state);
		dbg("PCPROT: $self->{call}/" . $r->call . ' rejected by in_filter_route') if !$filter && isdbg('chanerr');
	}
	return $filter;
}

sub eph_dup
{
	my $s = shift;
	my $t = shift || $eph_restime;
	my $r;

	# chop the end off
	$s =~ s/\^H\d\d?\^?\~?$//;
	$r = 1 if exists $eph{$s};    # pump up the dup if it keeps circulating
	$eph{$s} = $main::systime + $t;
	dbg("PCPROT: emphemeral duplicate") if $r && isdbg('chanerr'); 
	return $r;
}

sub eph_del_regex
{
	my $regex = shift;
	my ($key, $val);
	while (($key, $val) = each %eph) {
		if ($key =~ m{$regex}) {
			delete $eph{$key};
		}
	}
}

sub eph_clean
{
	my ($key, $val);
	
	while (($key, $val) = each %eph) {
		if ($main::systime >= $val) {
			delete $eph{$key};
		}
	}
}

sub eph_list
{
	my ($key, $val);
	my @out;

	while (($key, $val) = each %eph) {
		push @out, $key, $val;
	}
	return @out;
}

sub run_cmd
{
	goto &DXCommandmode::run_cmd;
}


# import any msgs in the chat directory
# the messages are sent to the chat group which forms the
# the first part of the name (eg: solar.1243.txt would be
# sent to chat group SOLAR)
# 
# Each message found is sent: one non-blank line to one chat
# message. So 4 lines = 4 chat messages.
# 
# The special name LOCAL is for local users ANN
# The special name ALL is for ANN/FULL
# The special name SYSOP is for ANN/SYSOP
#
sub import_chat
{
	# are there any to do in this directory?
	return unless -d $chatimportfn;
	unless (opendir(DIR, $chatimportfn)) {
		dbg("can\'t open $chatimportfn $!") if isdbg('msg');
		Log('msg', "can\'t open $chatimportfn $!");
		return;
	} 

	my @names = readdir(DIR);
	closedir(DIR);
	my $name;
	foreach $name (@names) {
		next if $name =~ /^\./;
		my $splitit = $name =~ /^split/;
		my $fn = "$chatimportfn/$name";
		next unless -f $fn;
		unless (open(MSG, $fn)) {
	 		dbg("can\'t open import file $fn $!") if isdbg('msg');
			Log('msg', "can\'t open import file $fn $!");
			unlink($fn);
			next;
		}
		my @msg = map { s/\r?\n$//; $_ } <MSG>;
		close(MSG);
		unlink($fn);

		my @cat = split /\./, $name;
		my $target = uc $cat[0];

		foreach my $text (@msg) {
			next unless $text && $text !~ /^\s*#/;
			if ($target eq 'ALL' || $target eq 'LOCAL' || $target eq 'SYSOP') {
				my $sysopflag = $target eq 'SYSOP' ? '*' : ' ';
				if ($target ne 'LOCAL') {
					send_announce($main::me, pc12($main::mycall, $text, '*', $sysopflag), $main::mycall, '*', $text, $sysopflag, $main::mycall, '0');
				} else {
					Log('ann', 'LOCAL', $main::mycall, $text);
					DXChannel::broadcast_list("To LOCAL de ${main::mycall}: $text\a", 'ann', undef, DXCommandmode->get_all());
				}
			} else {
				my $msgid = nextchatmsgid();
				$text = "#$msgid $text";
				send_chat($main::me, pc12($main::mycall, $text, '*', $target), $main::mycall, '*', $text, $target, $main::mycall, '0');
			}
		}
	}
}

1;
__END__ 
