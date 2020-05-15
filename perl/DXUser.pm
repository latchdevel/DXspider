#
# DX cluster user routines
#
# Copyright (c) 1998 - Dirk Koopman G1TLH
#
#
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

use strict;

use vars qw(%u $dbm $filename %valid $lastoperinterval $lasttime $lru $lrusize $tooold $v3 $v4);

%u = ();
$dbm = undef;
$filename = undef;
$lastoperinterval = 60*24*60*60;
$lasttime = 0;
$lrusize = 2000;
$tooold = 86400 * 365 + 31;		# this marks an old user who hasn't given enough info to be useful
$v3 = 0;
$v4 = 0;
my $json;

our $maxconnlist = 3;			# remember this many connection time (duration) [start, end] pairs

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
  
	my $ufn;
	my $convert;
	
	my $fn = "users";

	$json = JSON->new();
	$filename = $ufn = localdata("$fn.json");
	
	if (-e localdata("$fn.json")) {
		$v4 = 1;
	} else {
		eval {
			require Storable;
		};

		if ($@) {
			if ( ! -e localdata("users.v3") && -e localdata("users.v2") ) {
				$convert = 2;
			}
			LogDbg('',"the module Storable appears to be missing!!");
			LogDbg('',"trying to continue in compatibility mode (this may fail)");
			LogDbg('',"please install Storable from CPAN as soon as possible");
		}
		else {
			import Storable qw(nfreeze thaw);
			$convert = 3 if -e localdata("users.v3") && !-e $ufn;
		}
	}

	# do a conversion if required
	if ($convert) {
		my ($key, $val, $action, $count, $err) = ('','',0,0,0);
		my $ta = [gettimeofday];
		
		my %oldu;
		LogDbg('',"Converting the User File from V$convert to $fn.json ");
		LogDbg('',"This will take a while, I suggest you go and have cup of strong tea");
		my $odbm = tie (%oldu, 'DB_File', localdata("users.v$convert"), O_RDONLY, 0666, $DB_BTREE) or confess "can't open user file: $fn.v$convert ($!) [rebuild it from user_asc?]";
        for ($action = R_FIRST; !$odbm->seq($key, $val, $action); $action = R_NEXT) {
			my $ref;
			if ($convert == 3) {
				eval { $ref = storable_decode($val) };
			} else {
				eval { $ref = asc_decode($val) };
			}
			unless ($@) {
				if ($ref) {
					$u{$key} = $ref;
					$count++;
				} else {
					$err++
				}
			} else {
				Log('err', "DXUser: error decoding $@");
			}
		} 
		undef $odbm;
		untie %oldu;
		my $t = _diffms($ta);
		LogDbg('',"Conversion from users.v$convert to users.json completed $count records $err errors $t mS");

		# now write it away for future use
		$ta = [gettimeofday];
		$err = 0;
		$count = writeoutjson();
		$t = _diffms($ta);
		LogDbg('',"New Userfile users.json write completed $count records $err errors $t mS");
		LogDbg('',"Now restarting..");
		$main::ending = 10;
	} else {
		# otherwise (i.e normally) slurp it in
		readinjson();
	}
	$filename = $ufn;
}

sub del_file
{
	# with extreme prejudice
	if ($v3) {
		unlink "$main::data/users.v3";
		unlink "$main::local_data/users.v3";
	}
	if ($v4) {
		unlink "$main::data/users.v4";
		unlink "$main::local_data/users.v4";
	}
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
	undef $dbm;
	untie %u;
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
  
#	confess "can't create existing call $call in User\n!" if $u{$call};

	my $self = $pkg->alloc($call);
	$self->put;
	return $self;
}

#
# get - get an existing user - this seems to return a different reference everytime it is
#       called - see below
#

sub get
{
	my $call = uc shift;
	my $data;
	
	# is it in the LRU cache?
	my $ref = $u{$call} if exists $u{$call};
#	my $ref = $lru->get($call);
	return $ref if $ref && ref $ref eq 'DXUser';
	
	# search for it
	# unless ($dbm->get($call, $data)) {
	# 	eval { $ref = decode($data); };
		
	# 	if ($ref) {
	# 		if (!UNIVERSAL::isa($ref, 'DXUser')) {
	# 			dbg("DXUser::get: got strange answer from decode of $call". ref $ref. " ignoring");
	# 			return undef;
	# 		}
	# 		# we have a reference and it *is* a DXUser
	# 	} else {
	# 		if ($@) {
	# 			LogDbg('err', "DXUser::get decode error on $call '$@'");
	# 		} else {
	# 			dbg("DXUser::get: no reference returned from decode of $call $!");
	# 		}
	# 		return undef;
	# 	}
	# 	$lru->put($call, $ref);
	# 	return $ref;
	# }
	return undef;
}

#
# get an existing either from the channel (if there is one) or from the database
#
# It is important to note that if you have done a get (for the channel say) and you
# want access or modify that you must use this call (and you must NOT use get's all
# over the place willy nilly!)
#

sub get_current
{
	my $call = uc shift;
  
	my $dxchan = DXChannel::get($call);
	if ($dxchan) {
		my $ref = $dxchan->user;
		return $ref if $ref && UNIVERSAL::isa($ref, 'DXUser');

		dbg("DXUser::get_current: got invalid user ref for $call from dxchan $dxchan->{call} ". ref $ref. " ignoring");
	}
	return get($call);
}

#
# get all callsigns in the database 
#

sub get_all_calls
{
	return (sort keys %u);
}

#
# put - put a user
#

sub put
{
	my $self = shift;
	confess "Trying to put nothing!" unless $self && ref $self;
	my $call = $self->{call};
	$self->{lastin} = $main::systime;
}

# freeze the user
sub encode
{
	goto &json_encode if $v4;
	goto &asc_encode unless $v3;
	my $self = shift;
	return nfreeze($self);
}

# thaw the user
sub decode
{
	goto &json_decode if $v4;
	goto &storable_decode if $v3;
	goto &asc_decode;
}

# should now be obsolete for mojo branch build 238 and above
sub storable_decode
{
	my $ref;
	$ref = thaw(shift);
	return $ref;
}


#
# create a hash from a string (in ascii)
#
sub asc_decode
{
	my $s = shift;
	my $ref;
	$s =~ s/\%([0-9A-F][0-9A-F])/chr(hex($1))/eg;
	eval '$ref = ' . $s;
	if ($@) {
		LogDbg('err', "DXUser::asc_decode: on '$s' $@");
		$ref = undef;
	}
	return $ref;
}

sub json_decode
{
	my $s = shift;
    my $ref;
	eval { $ref = $json->decode($s) };
	if ($ref && !$@) {
        return bless $ref, 'DXUser';
	} else {
		LogDbg('err', "DXUser::json_decode: on '$s' $@");
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
#	$lru->remove($call);
	#	$dbm->del($call);
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
#	$self->put();
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

	my $fn = $name || "$main::local_data/user_json"; # force use of local_data
	
	# save old ones
	move "$fn.oooo", "$fn.ooooo" if -e "$fn.oooo";
	move "$fn.ooo", "$fn.oooo" if -e "$fn.ooo";
	move "$fn.oo", "$fn.ooo" if -e "$fn.oo";
	move "$fn.o", "$fn.oo" if -e "$fn.o";
	move "$fn", "$fn.o" if -e "$fn";

	my $json = JSON->new;
	$json->canonical(1);
	
	my $count = 0;
	my $err = 0;
	my $del = 0;
	my $fh = new IO::File ">$fn" or return "cannot open $fn ($!)";
	if ($fh) {
		my $key = 0;
		my $val = undef;
		foreach my $k (sort keys %u) {
			my $r = $u{$k};
			if ($r->{sort} eq 'U' && !$r->{priv} && $main::systime > $r->{lastin}+$tooold ) {
				unless ($r->{lat} || $r->{long} || $r->{qra} || $r->{qth} || $r->{name}) {
					LogDbg('err', "DXUser::export deleting $k - too old, last in " . cldatetime($r->lastin) . " " . difft([$r->lastin, $main::systime]));
					delete $u{$k};
					++$del;
					next;
				}
			}
			eval {$val = json_encode($r);};
			if ($@) {
				LogDbg('err', "DXUser::export error encoding call: $k $@");
				++$err;
				next;
			} 
			$fh->print("$k\t$val\n");
			++$count;
		}
        $fh->close;
    }
	my $s = qq{Exported users to $fn - $count Users $del Deleted $err Errors ('sh/log Export' for details)};
	LogDbg('command', $s);
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
}

sub unset_passphrase
{
	my $self = shift;
	delete $self->{passphrase};
}

sub set_believe
{
	my $self = shift;
	my $call = uc shift;
	$self->{believe} ||= [];
	push @{$self->{believe}}, $call unless grep $_ eq $call, @{$self->{believe}};
}

sub unset_believe
{
	my $self = shift;
	my $call = uc shift;
	if (exists $self->{believe}) {
		$self->{believe} = [grep {$_ ne $call} @{$self->{believe}}];
		delete $self->{believe} unless @{$self->{believe}};
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

sub readinjson
{
	my $fn = shift || $filename;
	
	my $ta = [gettimeofday];
	my $count = 0;
	my $s;
	my $err = 0;

	unless (-r $fn) {
		dbg("DXUser $fn not found - probably about to convert");
		return;
	}
	
	open DATA, "$fn" or die "$fn read error $!";
	while (<DATA>) {
		chomp;
		my @f = split /\t/;
		my $ref;
		eval { $ref = json_decode($f[1]); };
		if ($ref) {
			$u{$f[0]} = $ref;
			$count++;
		} else {
			LogDbg('DXCommand', "# readinjson Error: '$f[0]\t$f[1]' $@");
			$err++
		}
	}
	close DATA;
	$s = _diffms($ta);
	dbg("DXUser::readinjson $count records $s mS");
}

sub writeoutjson()
{
	my $fn = shift || $filename;

	link $fn, "$fn.o";
	unlink $fn;
	open DATA, ">$fn" or die "$fn write error $!";
	my $fh = new IO::File ">$fn" or return "cannot open $fn ($!)";
	my $count = 0;
	if ($fh) {
		my $key = 0;
		my $val = undef;
		foreach my $k (keys %u) { # this is to make it as quick as possible (no sort)
			my $r = $u{$k};
			$val = json_encode($r);
			$fh->print("$k\t$val\n");
			++$count;
		}
        $fh->close;
    }
	close DATA;
	return $count;
}
1;
__END__





