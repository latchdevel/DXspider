#
# module to manage channel lists & data
#
# This is the base class for all channel operations, which is everything to do 
# with input and output really.
#
# The instance variable in the outside world will be generally be called $dxchan
#
# This class is 'inherited' (if that is the goobledegook for what I am doing)
# by various other modules. The point to understand is that the 'instance variable'
# is in fact what normal people would call the state vector and all useful info
# about a connection goes in there.
#
# Another point to note is that a vector may contain a list of other vectors. 
# I have simply added another variable to the vector for 'simplicity' (or laziness
# as it is more commonly called)
#
# PLEASE NOTE - I am a C programmer using this as a method of learning perl
# firstly and OO about ninthly (if you don't like the design and you can't 
# improve it with better OO and thus make it smaller and more efficient, then tough). 
#
# Copyright (c) 1998-2000 - Dirk Koopman G1TLH
#
# $Id$
#
package DXChannel;

use Msg;
use DXM;
use DXUtil;
use DXVars;
use DXDebug;
use Filter;
use Prefix;
use Route;

use strict;
use vars qw(%channels %valid @ISA $count);

%channels = ();
$count = 0;

%valid = (
		  call => '0,Callsign',
		  conn => '9,Msg Conn ref',
		  user => '9,DXUser ref',
		  startt => '0,Start Time,atime',
		  t => '9,Time,atime',
		  pc50_t => '5,Last PC50 Time,atime',
		  priv => '9,Privilege',
		  state => '0,Current State',
		  oldstate => '5,Last State',
		  list => '9,Dep Chan List',
		  name => '0,User Name',
		  consort => '5,Connection Type',
		  'sort' => '5,Type of Channel',
		  wwv => '0,Want WWV,yesno',
		  wcy => '0,Want WCY,yesno',
		  wx => '0,Want WX,yesno',
		  talk => '0,Want Talk,yesno',
		  ann => '0,Want Announce,yesno',
		  here => '0,Here?,yesno',
		  conf => '0,In Conference?,yesno',
		  dx => '0,DX Spots,yesno',
		  redirect => '0,Redirect messages to',
		  lang => '0,Language',
		  func => '5,Function',
		  loc => '9,Local Vars', # used by func to store local variables in
		  beep => '0,Want Beeps,yesno',
		  lastread => '5,Last Msg Read',
		  outbound => '5,outbound?,yesno',
		  remotecmd => '9,doing rcmd,yesno',
		  pagelth => '0,Page Length',
		  pagedata => '9,Page Data Store',
		  group => '0,Access Group,parray',	# used to create a group of users/nodes for some purpose or other
		  isolate => '5,Isolate network,yesno',
		  delayed => '5,Delayed messages,parray',
		  annfilter => '5,Ann Filt-out',
		  wwvfilter => '5,WWV Filt-out',
		  wcyfilter => '5,WCY Filt-out',
		  spotsfilter => '5,Spot Filt-out',
		  routefilter => '5,Route Filt-out',
		  inannfilter => '5,Ann Filt-inp',
		  inwwvfilter => '5,WWV Filt-inp',
		  inwcyfilter => '5,WCY Filt-inp',
		  inspotsfilter => '5,Spot Filt-inp',
		  inroutefilter => '5,Route Filt-inp',
		  passwd => '9,Passwd List,parray',
		  pingint => '5,Ping Interval ',
		  nopings => '5,Ping Obs Count',
		  lastping => '5,Ping last sent,atime',
		  pingtime => '5,Ping totaltime,parray',
		  pingave => '0,Ping ave time',
		  logininfo => '9,Login info req,yesno',
		  talklist => '0,Talk List,parray',
		  cluster => '5,Cluster data',
		  isbasic => '9,Internal Connection', 
		  errors => '9,Errors',
		  route => '9,Route Data',
		  dxcc => '0,Country Code',
		  itu => '0,ITU Zone',
		  cq => '0,CQ Zone',
		  enhanced => '5,Enhanced Client,yesno',
		  senddbg => '8,Sending Debug,yesno',
		  width => '0,Column Width',
		  disconnecting => '9,Disconnecting,yesno',
		  ann_talk => '0,Suppress Talk Anns,yesno',
		 );

use vars qw($VERSION $BRANCH);
$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /\d+\.\d+\.(\d+)\.(\d+)/ ) || 0;
$main::build += $VERSION;
$main::branch += $BRANCH;

# object destruction
sub DESTROY
{
	my $self = shift;
	for (keys %$self) {
		if (ref($self->{$_})) {
			delete $self->{$_};
		}
	}
	dbg("DXChannel $self->{call} destroyed ($count)") if isdbg('chan');
	$count--;
}

# create a new channel object [$obj = DXChannel->new($call, $msg_conn_obj, $user_obj)]
sub alloc
{
	my ($pkg, $call, $conn, $user) = @_;
	my $self = {};
  
	die "trying to create a duplicate channel for $call" if $channels{$call};
	$self->{call} = $call;
	$self->{priv} = 0;
	$self->{conn} = $conn if defined $conn;	# if this isn't defined then it must be a list
	if (defined $user) {
		$self->{user} = $user;
		$self->{lang} = $user->lang;
		$user->new_group() if !$user->group;
		$self->{group} = $user->group;
		$self->{sort} = $user->sort;
	}
	$self->{startt} = $self->{t} = time;
	$self->{state} = 0;
	$self->{oldstate} = 0;
	$self->{lang} = $main::lang if !$self->{lang};
	$self->{func} = "";

	# add in all the dxcc, itu, zone info
	my @dxcc = Prefix::extract($call);
	if (@dxcc > 0) {
		$self->{dxcc} = $dxcc[1]->dxcc;
		$self->{itu} = $dxcc[1]->itu;
		$self->{cq} = $dxcc[1]->cq;						
	}

	$count++;
	dbg("DXChannel $self->{call} created ($count)") if isdbg('chan');
	bless $self, $pkg; 
	return $channels{$call} = $self;
}

# obtain a channel object by callsign [$obj = DXChannel->get($call)]
sub get
{
	my ($pkg, $call) = @_;
	return $channels{$call};
}

# obtain all the channel objects
sub get_all
{
	my ($pkg) = @_;
	return values(%channels);
}

#
# gimme all the ak1a nodes
#
sub get_all_nodes
{
	my $ref;
	my @out;
	foreach $ref (values %channels) {
		push @out, $ref if $ref->is_node;
	}
	return @out;
}

# return a list of all users
sub get_all_users
{
	my $ref;
	my @out;
	foreach $ref (values %channels) {
		push @out, $ref if $ref->is_user;
	}
	return @out;
}

# return a list of all user callsigns
sub get_all_user_calls
{
	my $ref;
	my @out;
	foreach $ref (values %channels) {
		push @out, $ref->{call} if $ref->is_user;
	}
	return @out;
}

# obtain a channel object by searching for its connection reference
sub get_by_cnum
{
	my ($pkg, $conn) = @_;
	my $self;
  
	foreach $self (values(%channels)) {
		return $self if ($self->{conn} == $conn);
	}
	return undef;
}

# get rid of a channel object [$obj->del()]
sub del
{
	my $self = shift;

	$self->{group} = undef;		# belt and braces
	delete $channels{$self->{call}};
}

# is it a bbs
sub is_bbs
{
	my $self = shift;
	return $self->{'sort'} eq 'B';
}

sub is_node
{
	my $self = shift;
	return $self->{'sort'} =~ /[ACRSX]/;
}
# is it an ak1a node ?
sub is_ak1a
{
	my $self = shift;
	return $self->{'sort'} eq 'A';
}

# is it a user?
sub is_user
{
	my $self = shift;
	return $self->{'sort'} eq 'U';
}

# is it a clx node
sub is_clx
{
	my $self = shift;
	return $self->{'sort'} eq 'C';
}

# is it a spider node
sub is_spider
{
	my $self = shift;
	return $self->{'sort'} eq 'S';
}

# is it a DXNet node
sub is_dxnet
{
	my $self = shift;
	return $self->{'sort'} eq 'X';
}

# is it a ar-cluster node
sub is_arcluster
{
	my $self = shift;
	return $self->{'sort'} eq 'R';
}

# for perl 5.004's benefit
sub sort
{
	my $self = shift;
	return @_ ? $self->{'sort'} = shift : $self->{'sort'} ;
}

# handle out going messages, immediately without waiting for the select to drop
# this could, in theory, block
sub send_now
{
	my $self = shift;
	my $conn = $self->{conn};
	return unless $conn;
	my $sort = shift;
	my $call = $self->{call};
	
	for (@_) {
#		chomp;
        my @lines = split /\n/;
		for (@lines) {
			$conn->send_now("$sort$call|$_");
			dbg("-> $sort $call $_") if isdbg('chan');
		}
	}
	$self->{t} = time;
}

#
# send later with letter (more control)
#

sub send_later
{
	my $self = shift;
	my $conn = $self->{conn};
	return unless $conn;
	my $sort = shift;
	my $call = $self->{call};
	
	for (@_) {
#		chomp;
        my @lines = split /\n/;
		for (@lines) {
			$conn->send_later("$sort$call|$_");
			dbg("-> $sort $call $_") if isdbg('chan');
		}
	}
	$self->{t} = time;
}

#
# the normal output routine
#
sub send						# this is always later and always data
{
	my $self = shift;
	my $conn = $self->{conn};
	return unless $conn;
	my $call = $self->{call};

	for (@_) {
#		chomp;
        my @lines = split /\n/;
		for (@lines) {
			$conn->send_later("D$call|$_");
			dbg("-> D $call $_") if isdbg('chan');
		}
	}
	$self->{t} = time;
}

# send a file (always later)
sub send_file
{
	my ($self, $fn) = @_;
	my $call = $self->{call};
	my $conn = $self->{conn};
	my @buf;
  
	open(F, $fn) or die "can't open $fn for sending file ($!)";
	@buf = <F>;
	close(F);
	$self->send(@buf);
}

# this will implement language independence (in time)
sub msg
{
	my $self = shift;
	return DXM::msg($self->{lang}, @_);
}

# stick a broadcast on the delayed queue (but only up to 20 items)
sub delay
{
	my $self = shift;
	my $s = shift;
	
	$self->{delayed} = [] unless $self->{delayed};
	push @{$self->{delayed}}, $s;
	if (@{$self->{delayed}} >= 20) {
		shift @{$self->{delayed}};   # lose oldest one
	}
}

# change the state of the channel - lots of scope for debugging here :-)
sub state
{
	my $self = shift;
	if (@_) {
		$self->{oldstate} = $self->{state};
		$self->{state} = shift;
		$self->{func} = '' unless defined $self->{func};
		dbg("$self->{call} channel func $self->{func} state $self->{oldstate} -> $self->{state}\n") if isdbg('state');

		# if there is any queued up broadcasts then splurge them out here
		if ($self->{delayed} && ($self->{state} eq 'prompt' || $self->{state} eq 'talk')) {
			$self->send (@{$self->{delayed}});
			delete $self->{delayed};
		}
	}
	return $self->{state};
}

# disconnect this channel
sub disconnect
{
	my $self = shift;
	my $user = $self->{user};
	
	$user->close() if defined $user;
	$self->{conn}->disconnect;
	$self->del();
}

#
# just close all the socket connections down without any fiddling about, cleaning, being
# nice to other processes and otherwise telling them what is going on.
#
# This is for the benefit of forked processes to prepare for starting new programs, they
# don't want or need all this baggage.
#

sub closeall
{
	my $ref;
	foreach $ref (values %channels) {
		$ref->{conn}->disconnect() if $ref->{conn};
	}
}

#
# Tell all the users that we have come in or out (if they want to know)
#
sub tell_login
{
	my ($self, $m) = @_;
	
	# send info to all logged in thingies
	my @dxchan = get_all_users();
	my $dxchan;
	foreach $dxchan (@dxchan) {
		next if $dxchan == $self;
		next if $dxchan->{call} eq $main::mycall;
		$dxchan->send($dxchan->msg($m, $self->{call})) if $dxchan->{logininfo};
	}
}

# various access routines

#
# return a list of valid elements 
# 

sub fields
{
	return keys(%valid);
}

#
# return a prompt for a field
#

sub field_prompt
{ 
	my ($self, $ele) = @_;
	return $valid{$ele};
}

# take a standard input message and decode it into its standard parts
sub decode_input
{
	my $dxchan = shift;
	my $data = shift;
	my ($sort, $call, $line) = $data =~ /^([A-Z])([A-Z0-9\-]{3,9})\|(.*)$/;

	my $chcall = (ref $dxchan) ? $dxchan->call : "UN.KNOWN";
	
	# the above regexp must work
	unless (defined $sort && defined $call && defined $line) {
#		$data =~ s/([\x00-\x1f\x7f-\xff])/uc sprintf("%%%02x",ord($1))/eg;
		dbg("DUFF Line on $chcall: $data") if isdbg('err');
		return ();
	}

	if(ref($dxchan) && $call ne $chcall) {
		dbg("DUFF Line come in for $call on wrong channel $chcall") if isdbg('err');
		return();
	}
	
	return ($sort, $call, $line);
}

sub rspfcheck
{
	my ($self, $flag, $node, $user) = @_;
	my $nref = Route::Node::get($node);
	if ($nref) {
	    if ($nref->dxchan == $self) {
			return 1 unless $user;
			my @users = $nref->users;
			return 1 if @users == 0 || grep $user eq $_, @users;
			dbg("RSPF: $user not on $node") if isdbg('rspf');
		} else {
			dbg("RSPF: Shortest path for $node is " . $nref->dxchan->{call}) if isdbg('rspf');
		}
	} else {
		return 1 if $flag;
		dbg("RSPF: required $node not found" ) if isdbg('rspf');
	}
	return 0;
}

no strict;
sub AUTOLOAD
{
	my $self = shift;
	my $name = $AUTOLOAD;
	return if $name =~ /::DESTROY$/;
	$name =~ s/.*:://o;
  
	confess "Non-existant field '$AUTOLOAD'" if !$valid{$name};

	# this clever line of code creates a subroutine which takes over from autoload
	# from OO Perl - Conway
	*{$AUTOLOAD} = sub {@_ > 1 ? $_[0]->{$name} = $_[1] : $_[0]->{$name}} ;
    @_ ? $self->{$name} = shift : $self->{$name} ;
}


1;
__END__;
