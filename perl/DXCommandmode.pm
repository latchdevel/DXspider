#!/usr/bin/perl
#
# This module impliments the user facing command mode for a dx cluster
#
# Copyright (c) 1998 Dirk Koopman G1TLH
#
# $Id$
# 

package DXCommandmode;

use POSIX;

@ISA = qw(DXChannel);

use DXUtil;
use DXChannel;
use DXUser;
use DXVars;
use DXDebug;
use DXM;
use DXLog;
use DXLogPrint;
use DXBearing;
use CmdAlias;
use Filter;
use Minimuf;
use DXDb;
use AnnTalk;
use WCY;
use Sun;
use Internet;

use strict;
use vars qw(%Cache %cmd_cache $errstr %aliases $scriptbase $maxerrors);

%Cache = ();					# cache of dynamically loaded routine's mod times
%cmd_cache = ();				# cache of short names
$errstr = ();					# error string from eval
%aliases = ();					# aliases for (parts of) commands
$scriptbase = "$main::root/scripts"; # the place where all users start scripts go
$maxerrors = 20;				# the maximum number of concurrent errors allowed before disconnection

#
# obtain a new connection this is derived from dxchannel
#

sub new 
{
	my $self = DXChannel::alloc(@_);

	# routing, this must go out here to prevent race condx
	my $pkg = shift;
	my $call = shift;
	my @rout = $main::routeroot->add_user($call, Route::here(1));
	DXProt::route_pc16($DXProt::me, $main::routeroot, @rout) if @rout;

	return $self;
}

# this is how a a connection starts, you get a hello message and the motd with
# possibly some other messages asking you to set various things up if you are
# new (or nearly new and slacking) user.

sub start
{ 
	my ($self, $line, $sort) = @_;
	my $user = $self->{user};
	my $call = $self->{call};
	my $name = $user->{name};
	
	$self->{name} = $name ? $name : $call;
	$self->send($self->msg('l2',$self->{name}));
	$self->send_file($main::motd) if (-e $main::motd);
	$self->state('prompt');		# a bit of room for further expansion, passwords etc
	$self->{priv} = $user->priv || 0;
	$self->{lang} = $user->lang || $main::lang || 'en';
	$self->{pagelth} = $user->pagelth || 20;
	$self->{priv} = 0 if $line =~ /^(ax|te)/; # set the connection priv to 0 - can be upgraded later
	$self->{consort} = $line;	# save the connection type
	
	# set some necessary flags on the user if they are connecting
	$self->{beep} = $user->wantbeep;
	$self->{ann} = $user->wantann;
	$self->{wwv} = $user->wantwwv;
	$self->{wcy} = $user->wantwcy;
	$self->{talk} = $user->wanttalk;
	$self->{wx} = $user->wantwx;
	$self->{dx} = $user->wantdx;
	$self->{logininfo} = $user->wantlogininfo;
	$self->{here} = 1;

	# get the filters
	$self->{spotsfilter} = Filter::read_in('spots', $call, 0) || Filter::read_in('spots', 'user_default', 0);
	$self->{wwvfilter} = Filter::read_in('wwv', $call, 0) || Filter::read_in('wwv', 'user_default', 0);
	$self->{wcyfilter} = Filter::read_in('wcy', $call, 0) || Filter::read_in('wcy', 'user_default', 0);
	$self->{annfilter} = Filter::read_in('ann', $call, 0) || Filter::read_in('ann', 'user_default', 0) ;

	# clean up qra locators
	my $qra = $user->qra;
	$qra = undef if ($qra && !DXBearing::is_qra($qra));
	unless ($qra) {
		my $lat = $user->lat;
		my $long = $user->long;
		$user->qra(DXBearing::lltoqra($lat, $long)) if (defined $lat && defined $long);  
	}

	$DXProt::me->conn($self->conn) if $call eq $main::myalias; # send all output for mycall to myalias

	Log('DXCommand', "$call connected");

	# send prompts and things
	my $info = Route::cluster();
	$self->send("Cluster:$info");
	$self->send($self->msg('namee1')) if !$user->name;
	$self->send($self->msg('qthe1')) if !$user->qth;
	$self->send($self->msg('qll')) if !$user->qra || (!$user->lat && !$user->long);
	$self->send($self->msg('hnodee1')) if !$user->qth;
	$self->send($self->msg('m9')) if DXMsg::for_me($call);
	$self->prompt;

	# decide on echo
	if (!$user->wantecho) {
		$self->send_now('E', "0");
		$self->send($self->msg('echow'));
	}
	
	$self->tell_login('loginu');
	
}

#
# This is the normal command prompt driver
#

sub normal
{
	my $self = shift;
	my $cmdline = shift;
	my @ans;
	
	# remove leading and trailing spaces
	$cmdline =~ s/^\s*(.*)\s*$/$1/;
	
	if ($self->{state} eq 'page') {
		my $i = $self->{pagelth};
		my $ref = $self->{pagedata};
		my $tot = @$ref;
		
		# abort if we get a line starting in with a
		if ($cmdline =~ /^a/io) {
			undef $ref;
			$i = 0;
		}
        
		# send a tranche of data
		while ($i-- > 0 && @$ref) {
			my $line = shift @$ref;
			$line =~ s/\s+$//o;	# why am having to do this? 
			$self->send($line);
		}
		
		# reset state if none or else chuck out an intermediate prompt
		if ($ref && @$ref) {
			$tot -= $self->{pagelth};
			$self->send($self->msg('page', $tot));
		} else {
			$self->state('prompt');
		}
	} elsif ($self->{state} eq 'sysop') {
		my $passwd = $self->{user}->passwd;
		my @pw = split / */, $passwd;
		if ($passwd) {
			my @l = @{$self->{passwd}};
			my $str = "$pw[$l[0]].*$pw[$l[1]].*$pw[$l[2]].*$pw[$l[3]].*$pw[$l[4]]";
			if ($cmdline =~ /$str/) {
				$self->{priv} = $self->{user}->priv;
			} else {
				$self->send($self->msg('sorry'));
			}
		} else {
			$self->send($self->msg('sorry'));
		}
		delete $self->{passwd};
		$self->state('prompt');
	} elsif ($self->{state} eq 'talk') {
		if ($cmdline =~ m{^(?:/EX|/ABORT)}i) {
			for (@{$self->{talklist}}) {
				$self->send_talks($_,  $self->msg('talkend'));
			}
			$self->state('prompt');
			delete $self->{talklist};
		} elsif ($cmdline =~ m(^/\w+)) {
			$cmdline =~ s(^/)();
			$self->send_ans(run_cmd($self, $cmdline));
			$self->send($self->talk_prompt);
		} elsif ($self->{talklist} && @{$self->{talklist}}) {
			# send what has been said to whoever is in this person's talk list
			for (@{$self->{talklist}}) {
				$self->send_talks($_, $cmdline);
			}
			$self->send($self->talk_prompt) if $self->{state} eq 'talk';
		} else {
			# for safety
			$self->state('prompt');
		}
	} else {
		$self->send_ans(run_cmd($self, $cmdline));
	} 
	
	# send a prompt only if we are in a prompt state
	$self->prompt() if $self->{state} =~ /^prompt/o;
}

# send out the talk messages taking into account vias and connectivity
sub send_talks
{
	my ($self, $ent, $line) = @_;
	
	my ($to, $via) = $ent =~ /(\S+)>(\S+)/;
	$to = $ent unless $to;
	my $call = $via ? $via : $to;
	my $clref = Route::get($call);
	my $dxchan = $clref->dxchan if $clref;
	if ($dxchan) {
		$dxchan->talk($self->{call}, $to, $via, $line);
	} else {
		$self->send($self->msg('disc2', $via ? $via : $to));
		my @l = grep { $_ ne $ent } @{$self->{talklist}};
		if (@l) {
			$self->{talklist} = \@l;
		} else {
			delete $self->{talklist};
			$self->state('prompt');
		}
	}
}

sub talk_prompt
{
	my $self = shift;
	my @call;
	for (@{$self->{talklist}}) {
		my ($to, $via) = /(\S+)>(\S+)/;
		$to = $_ unless $to;
		push @call, $to;
	}
	return $self->msg('talkprompt', join(',', @call));
}

#
# send a load of stuff to a command user with page prompting
# and stuff
#

sub send_ans
{
	my $self = shift;
	
	if ($self->{pagelth} && @_ > $self->{pagelth}) {
		my $i;
		for ($i = $self->{pagelth}; $i-- > 0; ) {
			my $line = shift @_;
			$line =~ s/\s+$//o;	# why am having to do this? 
			$self->send($line);
		}
		$self->{pagedata} =  [ @_ ];
		$self->state('page');
		$self->send($self->msg('page', scalar @_));
	} else {
		for (@_) {
			$self->send($_) if $_;
		}
	} 
}
# 
# this is the thing that runs the command, it is done like this for the 
# benefit of remote command execution
#

sub run_cmd
{
	my $self = shift;
	my $user = $self->{user};
	my $call = $self->{call};
	my $cmdline = shift;
	my @ans;
	
	if ($self->{func}) {
		my $c = qq{ \@ans = $self->{func}(\$self, \$cmdline) };
		dbg("stored func cmd = $c\n") if isdbg('eval');
		eval  $c;
		if ($@) {
			return ("Syserr: Eval err $errstr on stored func $self->{func}", $@);
		}
	} else {

		return () if length $cmdline == 0;
		
		# strip out //
		$cmdline =~ s|//|/|og;
		
		# split the command line up into parts, the first part is the command
		my ($cmd, $args) = split /\s+/, $cmdline, 2;
		$args = "" unless defined $args;
		
		if ($cmd) {
			
			my ($path, $fcmd);
			
			dbg("cmd: $cmd") if isdbg('command');
			
			# alias it if possible
			my $acmd = CmdAlias::get_cmd($cmd);
			if ($acmd) {
				($cmd, $args) = split /\s+/, "$acmd $args", 2;
				$args = "" unless defined $args;
				dbg("aliased cmd: $cmd $args") if isdbg('command');
			}
			
			# first expand out the entry to a command
			($path, $fcmd) = search($main::localcmd, $cmd, "pl");
			($path, $fcmd) = search($main::cmd, $cmd, "pl") if !$path || !$fcmd;

			if ($path && $cmd) {
				dbg("path: $cmd cmd: $fcmd") if isdbg('command');
			
				my $package = find_cmd_name($path, $fcmd);
				@ans = (0) if !$package ;
				
				if ($package) {
					dbg("package: $package") if isdbg('command');
					my $c;
					unless (exists $Cache{$package}->{'sub'}) {
						$c = eval $Cache{$package}->{'eval'};
						if ($@) {
							return DXDebug::shortmess($@);
						}
						$Cache{$package}->{'sub'} = $c;
					}
					$c = $Cache{$package}->{'sub'};
					eval {
						@ans = &{$c}($self, $args);
				    };
					
					if ($@) {
						#cluck($@);
						return (DXDebug::shortmess($@));
					};
				}
			} else {
				dbg("cmd: $cmd not found") if isdbg('command');
				if (++$self->{errors} > $maxerrors) {
					$self->send($self->msg('e26'));
					$self->disconnect;
					return ();
				} else {
					return ($self->msg('e1'));
				}
			}
		}
	}
	
	my $ok = shift @ans;
	if ($ok) {
		delete $self->{errors};
	} else {
		if (++$self->{errors} > $maxerrors) {
			$self->send($self->msg('e26'));
			$self->disconnect;
			return ();
		}
	}
	return (@ans);
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
		next if $dxchan->sort ne 'U';  
		
		# send a prompt if no activity out on this channel
		if ($t >= $dxchan->t + $main::user_interval) {
			$dxchan->prompt() if $dxchan->{state} =~ /^prompt/o;
			$dxchan->t($t);
		}
	}
}

#
# finish up a user context
#
sub disconnect
{
	my $self = shift;
	my $call = $self->call;

	# reset the redirection of messages back to 'normal' if we are the sysop
	if ($call eq $main::myalias) {
		$DXProt::me->conn(undef);
	}

	my @rout = $main::routeroot->del_user($call);
	dbg("B/C PC17 on $main::mycall for: $call") if isdbg('route');

	# issue a pc17 to everybody interested
	DXProt::route_pc17($DXProt::me, $main::routeroot, @rout) if @rout;

	# I was the last node visited
    $self->user->node($main::mycall);
		
	# send info to all logged in thingies
	$self->tell_login('logoutu');

	Log('DXCommand', "$call disconnected");

	$self->SUPER::disconnect;
}

#
# short cut to output a prompt
#

sub prompt
{
	my $self = shift;
	$self->send($self->msg($self->here ? 'pr' : 'pr2', $self->call, cldate($main::systime), ztime($main::systime)));
}

# broadcast a message to all users [except those mentioned after buffer]
sub broadcast
{
	my $pkg = shift;			# ignored
	my $s = shift;				# the line to be rebroadcast
	my @except = @_;			# to all channels EXCEPT these (dxchannel refs)
	my @list = DXChannel->get_all(); # just in case we are called from some funny object
	my ($dxchan, $except);
	
 L: foreach $dxchan (@list) {
		next if !$dxchan->sort eq 'U'; # only interested in user channels  
		foreach $except (@except) {
			next L if $except == $dxchan;	# ignore channels in the 'except' list
		}
		$dxchan->send($s);			# send it
	}
}

# gimme all the users
sub get_all
{
	my @list = DXChannel->get_all();
	my $ref;
	my @out;
	foreach $ref (@list) {
		push @out, $ref if $ref->sort eq 'U';
	}
	return @out;
}

# run a script for this user
sub run_script
{
	my $self = shift;
	my $silent = shift || 0;
	
}

#
# search for the command in the cache of short->long form commands
#

sub search
{
	my ($path, $short_cmd, $suffix) = @_;
	my ($apath, $acmd);
	
	# commands are lower case
	$short_cmd = lc $short_cmd;
	dbg("command: $path $short_cmd\n") if isdbg('command');

	# do some checking for funny characters
	return () if $short_cmd =~ /\/$/;

	# return immediately if we have it
	($apath, $acmd) = split ',', $cmd_cache{$short_cmd} if $cmd_cache{$short_cmd};
	if ($apath && $acmd) {
		dbg("cached $short_cmd = ($apath, $acmd)\n") if isdbg('command');
		return ($apath, $acmd);
	}
	
	# if not guess
	my @parts = split '/', $short_cmd;
	my $dirfn;
	my $curdir = $path;
	my $p;
	my $i;
	my @lparts;
	
	for ($i = 0; $i < @parts; $i++) {
		my  $p = $parts[$i];
		opendir(D, $curdir) or confess "can't open $curdir $!";
		my @ls = readdir D;
		closedir D;
		my $l;
		foreach $l (sort @ls) {
			next if $l =~ /^\./;
			if ($i < $#parts) {            	# we are dealing with directories
				if ((-d "$curdir/$l") && $p eq substr($l, 0, length $p)) {
					dbg("got dir: $curdir/$l\n") if isdbg('command');
					$dirfn .= "$l/";
					$curdir .= "/$l";
					last;
				}
			} else {			# we are dealing with commands
				@lparts = split /\./, $l;                  
				next if $lparts[$#lparts] ne $suffix;        # only look for .$suffix files
				if ($p eq substr($l, 0, length $p)) {
					pop @lparts; #  remove the suffix
					$l = join '.', @lparts;
					#		  chop $dirfn;               # remove trailing /
					$dirfn = "" unless $dirfn;
					$cmd_cache{"$short_cmd"} = join(',', ($path, "$dirfn$l")); # cache it
					dbg("got path: $path cmd: $dirfn$l\n") if isdbg('command');
					return ($path, "$dirfn$l"); 
				}
			}
		}
	}
	return ();  
}  

# clear the command name cache
sub clear_cmd_cache
{
	%cmd_cache = ();
}

#
# the persistant execution of things from the command directories
#
#
# This allows perl programs to call functions dynamically
# 
# This has been nicked directly from the perlembed pages
#

#require Devel::Symdump;  

sub valid_package_name {
	my($string) = @_;
	$string =~ s/([^A-Za-z0-9\/])/sprintf("_%2x",unpack("C",$1))/eg;
	
	#second pass only for words starting with a digit
	$string =~ s|/(\d)|sprintf("/_%2x",unpack("C",$1))|eg;
	
	#Dress it up as a real package name
	$string =~ s/\//_/og;
	return $string;
}

# find a cmd reference
# this is really for use in user written stubs
#
# use the result as a symbolic reference:-
#
# no strict 'refs';
# @out = &$r($self, $line);
#
sub find_cmd_ref
{
	my $cmd = shift;
	my $r;
	
	if ($cmd) {
		
		# first expand out the entry to a command
		my ($path, $fcmd) = search($main::localcmd, $cmd, "pl");
		($path, $fcmd) = search($main::cmd, $cmd, "pl") if !$path || !$fcmd;
		
		# make sure it is loaded
		$r = find_cmd_name($path, $fcmd);
	}
	return $r;
}

# 
# this bit of magic finds a command in the offered directory
sub find_cmd_name {
	my $path = shift;
	my $cmdname = shift;
	my $package = valid_package_name($cmdname);
	my $filename = "$path/$cmdname.pl";
	my $mtime = -M $filename;
	
	# return if we can't find it
	$errstr = undef;
	unless (defined $mtime) {
		$errstr = DXM::msg('e1');
		return undef;
	}
	
	if(defined $Cache{$package}->{mtime} &&$Cache{$package}->{mtime} <= $mtime) {
		#we have compiled this subroutine already,
		#it has not been updated on disk, nothing left to do
		#print STDERR "already compiled $package->handler\n";
		;
	} else {

		my $sub = readfilestr($filename);
		unless ($sub) {
			$errstr = "Syserr: can't open '$filename' $!";
			return undef;
		};
		
		#wrap the code into a subroutine inside our unique package
		my $eval = qq( sub { $sub } );
		
		if (isdbg('eval')) {
			my @list = split /\n/, $eval;
			my $line;
			for (@list) {
				dbg($_ . "\n") if isdbg('eval');
			}
		}
		
		$Cache{$package} = {mtime => $mtime, 'eval' => $eval };
	}

	return $package;
}

# send a talk message here
sub talk
{
	my ($self, $from, $to, $via, $line) = @_;
	$line =~ s/\\5E/\^/g;
	$self->send("$to de $from: $line") if $self->{talk};
	Log('talk', $to, $from, $main::mycall, $line);
}

# send an announce
sub announce
{

}

# send a dx spot
sub dx_spot
{
	
}

1;
__END__
