#
# DX cluster user routines
#
# Copyright (c) 1998-2020 - Dirk Koopman G1TLH
#
# The new internal structure of the users system looks like this:
#
# The users.v4 file formatted as a file of lines containing: <callsign>\t{json serialised version of user record}\n
#
# You can look at it with any text tools or your favourite editor :-)
#
# In terms of internal structure, the main user hash remains as %u, keyed on callsign as before.
#
# The value is a one or two element array [position] or [position, ref], depending on whether the record has been "get()ed"
# [i.e. got from disk] or not. The 'position' is simply the start of each line in the file. The function "get()" simply returns
# the stored reference in array[1], if present, or seeks to the  position from array[0], reads a line, json_decodes it,
# stores that reference into array[1] and returns that. That reference will be used from that time onwards.
#
# The routine writeoutjson() will (very) lazily write out a copy of %u WITHOUT STORING ANY EXTRA CURRENTLY UNREFERENCED CALLSIGN
# records to users.v4.n. It, in effect, does a sort of random accessed merge of the current user file and any "in memory"
# versions of any user record. This can be done with a spawned command because it will just be reading %u and merging
# loaded records, not altering the current users.v4 file in any way. 
#
# %u -> $u{call} -> [position of json line in users.v4 (, reference -> {call=>'G1TLH', ...} if this record is in use)].
#
# On my machine, it takes about 250mS to read the entire users.v4 file of 190,000 records and to create a
# $u{callsign}->[record position in users.v4] for every callsign in the users.v4 file. Loading ~19,000 records
# (read from disk, decode json, store reference) takes about 110mS (or 580nS/record).
#
# A periodic dump of users.v4.n, with said ~19,000 records in memory takes about 750mS to write (this can be speeded up,
# by at least a half, if it becomes a problem!). As this periodic dump will be spawned off, it will not interrupt the data
# stream.
#
# This is the first rewrite of DXUsers since inception. In the mojo branch we will no longer use Storable but use JSON instead.
# We will now be storing all the keys in memory and will use opportunistic loading of actual records in "get()". So out of
# say 200,000 known users it is unlikely that we will have more than 10% (more likely less) of the user records in memory.
# This will mean that there will be a increase in memory requirement, but it is modest. I estimate it's unlikely be more
# than 30 or so MB.
#
# At the moment that means that the working users.v4 is "immutable". 
#
# In normal operation, when first calling 'init()', the keys and positions will be read from the newer of users.v4.n and
# users.v4. If there is no users.v4.n, then users.v4 will be used. As time wears on, %u will then accrete active user records.
# Once an hour the current %u will be saved to users.v4.n.
#
# If it becomes too much of a problem then we are likely to chuck off "close()d" users onto the end of the current users.v4
# leaving existing users intact, but updating the pointer to the (now cleared out) user ref to the new location. This will
# be a sort of write behind log file. The users.v4 file is still immutable for the starting positions, but any chucked off
# records (or even "updates") will be written to the end of that file. If this has to be reread at any time, then the last
# entry for any callsign "wins". But this will only happen if I think the memory requirements over time become too much. 
#
# As there is no functional difference between the users.v4 and export_user generated "user_json" file(s), other than the latter
# will be in sorted order with the record elements in "canonical" order. There will now longer be any code to execute to
# "restore the users file". Simply copy one of the "user_json" files to users.v4, remove users.v4.n and restart. 
#
# Hopefully though, this will put to rest the need to do all that messing about ever again... Pigs may well be seen flying over
# your node as well :-)
#

package DXUser;

use DXLog;
use DB_File;
use Data::Dumper;
use Fcntl;
use IO::File;
use DXUtil;
use LRU;
use File::Copy;
use JSON;
use DXDebug;
use Data::Structure::Util qw(unbless);
use Time::HiRes qw(gettimeofday tv_interval);
use IO::File;

use strict;

use vars qw(%u  $filename %valid $lastoperinterval $lasttime $lru $lrusize $tooold $v3 $v4);

%u = ();
$filename = undef;
$lastoperinterval = 60*24*60*60;
$lasttime = 0;
$lrusize = 2000;
$tooold = 86400 * 365 + 31;		# this marks an old user who hasn't given enough info to be useful
$v3 = 0;
$v4 = 0;
my $json;

our $maxconnlist = 3;			# remember this many connection time (duration) [start, end] pairs

our $newusers = 0;					# per execution stats
our $modusers = 0;
our $totusers = 0;
our $delusers = 0;
our $cachedusers = 0;

my $ifh;						# the input file, initialised by readinjson()


# hash of valid elements and a simple prompt
%valid = (
		  call => '0,Callsign',
		  alias => '0,Real Callsign',
		  name => '0,Name',
		  qth => '0,Home QTH',
		  lat => '0,Latitude,slat',
		  long => '0,Longitude,slong',
		  qra => '0,Locator',
		  email => '0,E-mail Address,parray',
		  priv => '9,Privilege Level',
		  lastin => '0,Last Time in,cldatetime',
		  passwd => '9,Password,yesno',
		  passphrase => '9,Pass Phrase,yesno',
		  addr => '0,Full Address',
		  'sort' => '0,Type of User', # A - ak1a, U - User, S - spider cluster, B - BBS
		  xpert => '0,Expert Status,yesno',
		  bbs => '0,Home BBS',
		  node => '0,Last Node',
		  homenode => '0,Home Node',
		  lockout => '9,Locked out?,yesno',	# won't let them in at all
		  dxok => '9,Accept DX Spots?,yesno', # accept his dx spots?
		  annok => '9,Accept Announces?,yesno', # accept his announces?
		  lang => '0,Language',
		  hmsgno => '0,Highest Msgno',
		  group => '0,Group,parray',	# used to create a group of users/nodes for some purpose or other
		  buddies => '0,Buddies,parray',
		  isolate => '9,Isolate network,yesno',
		  wantbeep => '0,Req Beep,yesno',
		  wantann => '0,Req Announce,yesno',
		  wantwwv => '0,Req WWV,yesno',
		  wantwcy => '0,Req WCY,yesno',
		  wantecho => '0,Req Echo,yesno',
		  wanttalk => '0,Req Talk,yesno',
		  wantwx => '0,Req WX,yesno',
		  wantdx => '0,Req DX Spots,yesno',
		  wantemail => '0,Req Msgs as Email,yesno',
		  pagelth => '0,Current Pagelth',
		  pingint => '9,Node Ping interval',
		  nopings => '9,Ping Obs Count',
		  wantlogininfo => '0,Login Info Req,yesno',
          wantgrid => '0,Show DX Grid,yesno',
		  wantann_talk => '0,Talklike Anns,yesno',
		  wantpc16 => '9,Want Users from node,yesno',
		  wantsendpc16 => '9,Send PC16,yesno',
		  wantroutepc19 => '9,Route PC19,yesno',
		  wantusstate => '0,Show US State,yesno',
		  wantdxcq => '0,Show CQ Zone,yesno',
		  wantdxitu => '0,Show ITU Zone,yesno',
		  wantgtk => '0,Want GTK interface,yesno',
		  wantpc9x => '0,Want PC9X interface,yesno',
		  lastoper => '9,Last for/oper,cldatetime',
		  nothere => '0,Not Here Text',
		  registered => '9,Registered?,yesno',
		  prompt => '0,Required Prompt',
		  version => '1,Version',
		  build => '1,Build',
		  believe => '1,Believable nodes,parray',
		  lastping => '1,Last Ping at,ptimelist',
		  maxconnect => '1,Max Connections',
		  startt => '0,Start Time,cldatetime',
		  connlist => '1,Connections,parraydifft',
		 );

#no strict;
sub AUTOLOAD
{
	no strict;
	my $name = $AUTOLOAD;
  
	return if $name =~ /::DESTROY$/;
	$name =~ s/^.*:://o;
  
	confess "Non-existant field '$AUTOLOAD'" if !$valid{$name};
	# this clever line of code creates a subroutine which takes over from autoload
	# from OO Perl - Conway
	*$AUTOLOAD = sub {@_ > 1 ? $_[0]->{$name} = $_[1] : $_[0]->{$name}};
       goto &$AUTOLOAD;
}

#use strict;

#
# initialise the system
#
sub init
{
	my $mode = shift;
  
	my $convert = "$main::root/perl/convert-users-v3-to-v4.pl";
	my $export;
		
	$json = JSON->new()->canonical(1);
	$filename = localdata("users.v4");
	
	if (-e $filename || -e "$filename.n" || -e "$filename.o") {
		$v4 = 1;
	} else {
#		if (-e localdata('users.v3')) {
#			LogDbg('DXUser', "Converting " . localdata('users.v3') . " to new json version of users file, please wait");
#			if (-x $convert) {
#				system($convert);
#				++$export;
#			}
#		}
		
		die "User file $filename missing, please run $convert or copy a user_json backup from somewhere\n" unless -e "$filename.n" || -s $filename;
	}
	readinjson();
	copy $filename, "$filename.n" unless -e "$filename.n";
	export() if $export;
}

sub del_file
{
	# with extreme prejudice
	unlink "$main::data/users.v4";
	unlink "$main::local_data/users.v4";
}

#
# periodic processing
#
sub process
{
#	if ($main::systime > $lasttime + 15) {
#		#$dbm->sync if $dbm;
#		$lasttime = $main::systime;
#	}
}

#
# close the system
#

sub finish
{
	
	writeoutjson();
}

#
# new - create a new user
#

sub alloc
{
	my $pkg = shift;
	my $call = uc shift;
	my $self = bless {call => $call, 'sort'=>'U'}, $pkg;
	return $self;
}

sub new
{
	my $pkg = shift;
	my $call = shift;
	#  $call =~ s/-\d+$//o;
  
	confess "can't create existing call $call in User\n!" if $u{$call};

	my $self = $pkg->alloc($call);
	$u{$call} = [0, $self];
	$self->put;
	++$newusers;
	++$totusers;
	return $self;
}

#
# get - get an existing user - this seems to return a different reference everytime it is
#       called - see below
#

sub get
{
	my $call = uc shift;
	my $nodecode = shift;
	my $ref = $u{$call};
	return undef unless $ref;
	
	unless ($ref->[1]) {
		$ifh->seek($ref->[0], 0);
		my $l = $ifh->getline;
		if ($l) {
			my ($k,$s) = split /\t/, $l;
			return $s if $nodecode;
			my $j = json_decode($s);
			if ($j) {
				$ref->[1] = $j;
				++$cachedusers;
			}
		}
	} elsif ($nodecode) {
		return json_encode($ref->[1]);
	}
	return $ref->[1];
}

#
# get an "ephemeral" reference - i.e. this will give you new temporary copy of
# the call's user record, but without storing it (if it isn't already there)
#
# This is not as quick as get()! But it will allow safe querying of the
# user file. Probably in conjunction with get_some_calls feeding it.
#
# NOTE: for cached records this, in effect, is a faster version of Storable's
# dclone - only about 3.5 times as fast!
#

sub get_tmp
{
	my $call = uc shift;
	my $ref = $u{$call};
	if ($ref) {
		if ($ref->[1]) {
			return json_decode(json_encode($ref->[1]));
		}
		$ifh->seek($ref->[0], 0);
		my $l = $ifh->getline;
		if ($l) {
			my ($k,$s) = split /\t/, $l;
			my $j = json_decode($s);
			return $j;
		}
	}
	return undef;
}

#
# Master branch:
# get an existing record either from the channel (if there is one) or from the database
#
# It is important to note that if you have done a get (for the channel say) and you
# want access or modify that you must use this call (and you must NOT use get's all
# over the place willy nilly!)
#
# NOTE: mojo branch with newusers system:
# There is no longer any function difference between get_current()
# and get() as they will always reference the same record as held in %u. This is because
# there is no more (repeated) thawing of stored records from the underlying "database".
#
# BUT: notice the difference between this and the get_tmp() function. A get() will online an
# othewise unused record, so for poking around looking for that locked out user:
# MAKE SURE you use get_tmp(). It will likely still be quicker than DB_File and Storable!
#

sub get_current
{
	goto &get;
	
#	my $call = uc shift;
#  
#	my $dxchan = DXChannel::get($call);
#	if ($dxchan) {
#		my $ref = $dxchan->user;
#		return $ref if $ref && UNIVERSAL::isa($ref, 'DXUser');
#
#		dbg("DXUser::get_current: got invalid user ref for $call from dxchan $dxchan->{call} ". ref $ref. " ignoring");
#	}
#	return get($call);
}

#
# get all callsigns in the database 
#

sub get_all_calls
{
	return (sort keys %u);
}

#
# get some calls - provide a qr// style selector string as a partial key
#

sub get_some_calls
{
	my $pattern = shift || qr/.*/;
	return sort grep {$pattern} keys %u;
}

#
# if I understand the term correctly, this is a sort of monad.
#
# Scan through the whole user file and select records that you want
# to process further. This routine returns lines of json, yu
#
# the CODE ref should look like:
# sub {
#   my $key = shift;
# 	my $line = shift;
#   # maybe do a rough check to see if this is a likely candidate
#   return unless $line =~ /something/;
#   my $r = json_decode($l);
# 	return (condition ? wanted thing : ());
# }
#
	
sub scan
{
	my $c = shift;
	my @out;
	
	if (ref($c) eq 'CODE') {
		foreach my $k (get_all_calls()) {
			my $l = get($k, 1);	# get the offline json line or the jsoned online version
			push @out, $c->($k, $l) if $l;
		}
	} else {
		dbg("DXUser::scan supplied argument is not a code ref");
	}
	return @out;
}

#
# put - put a user
#

sub put
{
	my $self = shift;
	confess "Trying to put nothing!" unless $self && ref $self;
	$self->{lastin} = $main::systime;
	++$modusers;				# new or existing, it's still been modified
}

# freeze the user
sub encode
{
	goto &json_encode;
}

# thaw the user
sub decode
{
	goto &json_decode;
}

sub json_decode
{
	my $s = shift;
    my $ref;
	eval { $ref = $json->decode($s) };
	if ($ref && !$@) {
        return bless $ref, 'DXUser';
	} else {
		LogDbg('DXUser', "DXUser::json_decode: on '$s' $@");
	}
	return undef;
}

sub json_encode
{
	my $ref = shift;
	unbless($ref);
    my $s = $json->encode($ref);
	bless $ref, 'DXUser';
	return $s;
}
	
#
# del - delete a user
#

sub del
{
	my $self = shift;
	my $call = $self->{call};
	++$delusers;
	--$totusers;
	--$cachedusers if $u{$call}->[1];
	delete $u{$call};
}

#
# close - close down a user
#

sub close
{
	my $self = shift;
	my $startt = shift;
	my $ip = shift;
	$self->{lastin} = $main::systime;
	# add a record to the connect list
	my $ref = [$startt || $self->{startt}, $main::systime];
	push @$ref, $ip if $ip;
	push @{$self->{connlist}}, $ref;
	shift @{$self->{connlist}} if @{$self->{connlist}} > $maxconnlist;
}

#
# sync the database
#

sub sync
{
#	$dbm->sync;
}

#
# return a list of valid elements 
# 

sub fields
{
	return keys(%valid);
}


#
# export the database to an ascii file
#

sub export
{
	my $name = shift;

	my $fn = $name || localdata("user_json"); # force use of local_data
	my $ta = [gettimeofday];
	
	# save old ones
	move "$fn.oooo", "$fn.ooooo" if -e "$fn.oooo";
	move "$fn.ooo", "$fn.oooo" if -e "$fn.ooo";
	move "$fn.oo", "$fn.ooo" if -e "$fn.oo";
	move "$fn.o", "$fn.oo" if -e "$fn.o";
	move "$fn", "$fn.o" if -e "$fn";

	my $json = JSON->new;
	$json->canonical(1);;
	
	my $count = 0;
	my $err = 0;
	my $del = 0;
	my $fh = new IO::File ">$fn" or return "cannot open $fn ($!)";
	if ($fh) {
		my $key = 0;
		my $val = undef;
		foreach my $k (sort keys %u) {
			my $r = get($k);
			if ($r->{sort} eq 'U' && !$r->{priv} && $main::systime > $r->{lastin}+$tooold ) {
				unless ($r->{lat} || $r->{long} || $r->{qra} || $r->{qth} || $r->{name}) {
					LogDbg('export', "DXUser::export deleting $k - too old, last in " . cldatetime($r->lastin) . " " . difft([$r->lastin, $main::systime]));
					delete $u{$k};
					++$del;
					next;
				}
			}
			eval {$val = json_encode($r);};
			if ($@) {
				LogDbg('export', "DXUser::export error encoding call: $k $@");
				++$err;
				next;
			} 
			$fh->print("$k\t$val\n");
			++$count;
		}
        $fh->close;
    }
	my $t = _diffms($ta);
	my $s = qq{Exported users to $fn - $count Users $del Deleted $err Errors in $t mS ('sh/log Export' for details)};
	LogDbg('DXUser', $s);
	return $s;
}

#
# group handling
#

# add one or more groups
sub add_group
{
	my $self = shift;
	my $ref = $self->{group} || [ 'local' ];
	$self->{group} = $ref if !$self->{group};
	push @$ref, @_ if @_;
}

# remove one or more groups
sub del_group
{
	my $self = shift;
	my $ref = $self->{group} || [ 'local' ];
	my @in = @_;
	
	$self->{group} = $ref if !$self->{group};
	
	@$ref = map { my $a = $_; return (grep { $_ eq $a } @in) ? () : $a } @$ref;
}

# does this thing contain all the groups listed?
sub union
{
	my $self = shift;
	my $ref = $self->{group};
	my $n;
	
	return 0 if !$ref || @_ == 0;
	return 1 if @$ref == 0 && @_ == 0;
	for ($n = 0; $n < @_; ) {
		for (@$ref) {
			my $a = $_;
			$n++ if grep $_ eq $a, @_; 
		}
	}
	return $n >= @_;
}

# simplified group test just for one group
sub in_group
{
	my $self = shift;
	my $s = shift;
	my $ref = $self->{group};
	
	return 0 if !$ref;
	return grep $_ eq $s, $ref;
}

# set up a default group (only happens for them's that connect direct)
sub new_group
{
	my $self = shift;
	$self->{group} = [ 'local' ];
}

# set up empty buddies (only happens for them's that connect direct)
sub new_buddies
{
	my $self = shift;
	$self->{buddies} = [  ];
}

#
# return a prompt for a field
#

sub field_prompt
{ 
	my ($self, $ele) = @_;
	return $valid{$ele};
}

# some variable accessors
sub sort
{
	my $self = shift;
	@_ ? $self->{'sort'} = shift : $self->{'sort'} ;
}

# some accessors

# want is default = 1
sub _want
{
	my $n = shift;
	my $self = shift;
	my $val = shift;
	my $s = "want$n";
	$self->{$s} = $val if defined $val;
	return exists $self->{$s} ? $self->{$s} : 1;
}

# wantnot is default = 0
sub _wantnot
{
	my $n = shift;
	my $self = shift;
	my $val = shift;
	my $s = "want$n";
	$self->{$s} = $val if defined $val;
	return exists $self->{$s} ? $self->{$s} : 0;
}

sub wantbeep
{
	return _want('beep', @_);
}

sub wantann
{
	return _want('ann', @_);
}

sub wantwwv
{
	return _want('wwv', @_);
}

sub wantwcy
{
	return _want('wcy', @_);
}

sub wantecho
{
	return _want('echo', @_);
}

sub wantwx
{
	return _want('wx', @_);
}

sub wantdx
{
	return _want('dx', @_);
}

sub wanttalk
{
	return _want('talk', @_);
}

sub wantgrid
{
	return _want('grid', @_);
}

sub wantemail
{
	return _want('email', @_);
}

sub wantann_talk
{
	return _want('ann_talk', @_);
}

sub wantpc16
{
	return _want('pc16', @_);
}

sub wantsendpc16
{
	return _want('sendpc16', @_);
}

sub wantroutepc16
{
	return _want('routepc16', @_);
}

sub wantusstate
{
	return _want('usstate', @_);
}

sub wantdxcq
{
	return _want('dxcq', @_);
}

sub wantdxitu
{
	return _want('dxitu', @_);
}

sub wantgtk
{
	return _want('gtk', @_);
}

sub wantpc9x
{
	return _want('pc9x', @_);
}

sub wantlogininfo
{
	my $self = shift;
	my $val = shift;
	$self->{wantlogininfo} = $val if defined $val;
	return $self->{wantlogininfo};
}

sub is_node
{
	my $self = shift;
	return $self->{sort} =~ /^[ACRSX]$/;
}

sub is_local_node
{
	my $self = shift;
	return grep $_ eq 'local_node', @{$self->{group}};
}

sub is_user
{
	my $self = shift;
	return $self->{sort} =~ /^[UW]$/;
}

sub is_web
{
	my $self = shift;
	return $self->{sort} eq 'W';
}

sub is_bbs
{
	my $self = shift;
	return $self->{sort} eq 'B';
}

sub is_spider
{
	my $self = shift;
	return $self->{sort} eq 'S';
}

sub is_clx
{
	my $self = shift;
	return $self->{sort} eq 'C';
}

sub is_dxnet
{
	my $self = shift;
	return $self->{sort} eq 'X';
}

sub is_arcluster
{
	my $self = shift;
	return $self->{sort} eq 'R';
}

sub is_ak1a
{
	my $self = shift;
	return $self->{sort} eq 'A';
}

sub unset_passwd
{
	my $self = shift;
	delete $self->{passwd};
	$self->put;
}

sub unset_passphrase
{
	my $self = shift;
	delete $self->{passphrase};
	$self->put;
}

sub set_believe
{
	my $self = shift;
	my $call = uc shift;
	$self->{believe} ||= [];
	unless (grep $_ eq $call, @{$self->{believe}}) {
		push @{$self->{believe}}, $call;
		$self->put;
	};
}

sub unset_believe
{
	my $self = shift;
	my $call = uc shift;
	if (exists $self->{believe}) {
		$self->{believe} = [grep {$_ ne $call} @{$self->{believe}}];
		delete $self->{believe} unless @{$self->{believe}};
		$self->put;
	}
}

sub believe
{
	my $self = shift;
	return exists $self->{believe} ? @{$self->{believe}} : ();
}

sub lastping
{
	my $self = shift;
	my $call = shift;
	$self->{lastping} ||= {};
	$self->{lastping} = {} unless ref $self->{lastping};
	my $b = $self->{lastping};
	$b->{$call} = shift if @_;
	return $b->{$call};	
}

#
# read in the latest version of the user file. As this file is immutable, the file one really wants is
# a later (generated) copy. But, if the plain users.v4 file is all we have, we'll use that.
#

sub readinjson
{
	my $fn = $filename;
	my $nfn = "$fn.n";
	my $ofn = "$fn.o";

	my $ta = [gettimeofday];
	my $count = 0;
	my $s;
	my $err = 0;

	if (-e $nfn && -e $fn && (stat($nfn))[9] > (stat($fn))[9]) {
		# move the old file to .o
		unlink $ofn;
		move($fn, $ofn);
		move($nfn, $fn);
	};

	# if we don't have a users.v4 at this point, look for a backup users.v4.json, users.v4.n then users.v4.o
	unless (-e $fn) {
		move($nfn, $fn) unless -e $fn; 	# the users.v4 isn't there (maybe convert-users-v3-to-v4.pl
		move("$fn.json", $fn);			# from a run of convert-users-v3-to-v4.pl
		move($ofn, $fn) unless -e $fn;	# desperate now...
	}
	
	if ($ifh) {
		$ifh->seek(0, 0);
	} else {
		LogDbg("DXUser","DXUser::readinjson: opening $fn as users file");
		$ifh = IO::File->new("+<$fn") or die "Cannot open $fn ($!)";
	}
	my $pos = $ifh->tell;
	while (<$ifh>) {
		chomp;
		my @f = split /\t/;
		$u{$f[0]} = [$pos];
		$count++;
		$pos = $ifh->tell;
	}
	$ifh->seek(0, 0);

	# $ifh is "global" and should not be closed
	
	LogDbg('DXUser',"DXUser::readinjson $count record headers read from $fn in ". _diffms($ta) . " mS");
	return $totusers = $count;
}

#
# Write a newer copy of the users.v4 file to users.v4.n, which is what will be read in.
# This means that the existing users.v4 is not touched during a run of dxspider, or at least
# not yet.

sub writeoutjson
{
	my $ofn = shift || "$filename.n";
	my $ta = [gettimeofday];
	
	my $ofh = IO::File->new(">$ofn") or die "$ofn write error $!";
	my $count = 0;
	$ifh->seek(0, 0);
	for my $k (sort keys %u) {
		my $l = get($k, 1);
		if ($l) {
			chomp $l;
			print $ofh "$k\t$l\n";
			++$count;
		} else {
			LogDbg('DXUser', "DXUser::writeoutjson callsign $k not found")
		}
	}
	
	$ofh->close;
	LogDbg('DXUser',"DXUser::writeoutjson $count records written to $ofn in ". _diffms($ta) . " mS");
	return $count;
}
1;
__END__





