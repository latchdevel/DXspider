#!/usr/bin/perl -w
#
# Database Handler module for DXSpider
#
# Copyright (c) 1999 Dirk Koopman G1TLH
#

package DXDb;

use strict;
use DXVars;
use DXLog;
use DXUtil;
use DB_File;
use DXDebug;

use vars qw($opentime $dbbase %avail %valid $lastprocesstime $nextstream %stream);

$opentime = 5*60;				# length of time a database stays open after last access
$dbbase = "$main::root/db";		# where all the databases are kept;
%avail = ();					# The hash contains a list of all the databases
%valid = (
		  accesst => '9,Last Accs Time,atime',
		  createt => '9,Create Time,atime',
		  lastt => '9,Last Upd Time,atime',
		  name => '0,Name',
		  db => '9,DB Tied hash',
		  remote => '0,Remote Database',
		  pre => '0,Heading txt',
		  post => '0,Tail txt',
		  chain => '0,Search these,parray',
		  disable => '0,Disabled?,yesno',
		  nf => '0,Not Found txt',
		  cal => '0,No Key txt',
		  allowread => '9,Allowed read,parray',
		  denyread => '9,Deny read,parray',
		  allowupd => '9,Allow upd,parray',
		  denyupd => '9,Deny upd,parray',
		  fwdupd => '9,Forw upd to,parray',
		  template => '9,Upd Templates,parray',
		  te => '9,End Upd txt',
		  tae => '9,End App txt',
		  atemplate => '9,App Templates,parray',
		  help => '0,Help txt,parray',
		  localcmd => '0,Local Command',
		 );

$lastprocesstime = time;
$nextstream = 0;
%stream = ();

use vars qw($VERSION $BRANCH);

main::mkver($VERSION = q$Revision$);

# allocate a new stream for this request
sub newstream
{
	my $call = uc shift;
	my $n = ++$nextstream;
	$stream{$n} = { n=>$n, call=>$call, t=>$main::systime };
	return $n;
}

# delete a stream
sub delstream
{
	my $n = shift;
	delete $stream{$n};
}

# get a stream
sub getstream
{
	my $n = shift;
	return $stream{$n};
}

# load all the database descriptors
sub load
{
	my $s = readfilestr($dbbase, "dbs", "pl");
	if ($s) {
		my $a;
		eval "\$a = $s";
		confess $@ if $@;
		%avail = ( %$a ) if ref $a;
	}
}

# save all the database descriptors
sub save
{
	closeall();
	writefilestr($dbbase, "dbs", "pl", \%avail);
}

# get the descriptor of the database you want.
sub getdesc
{
	return undef unless %avail;
	
	my $name = lc shift;
	my $r = $avail{$name};

	# search for a partial if not found direct
	unless ($r) {
		for (sort { $a->{name} cmp $b->{name} }values %avail) {
			if ($_->{name} =~ /^$name/) {
				$r = $_;
				last;
			}
		}
	}
	return $r;
}

# open it
sub open
{
	my $self = shift;
	$self->{accesst} = $main::systime;
	return $self->{db} if $self->{db};
	my %hash;
	$self->{db} = tie %hash, 'DB_File', "$dbbase/$self->{name}";
#	untie %hash;
	return $self->{db};
}

# close it
sub close
{
	my $self = shift;
	if ($self->{db}) {
		undef $self->{db};
		delete $self->{db};
	}
}

# close all
sub closeall
{
	if (%avail) {
		for (values %avail) {
			$_->close();
		}
	}
}

# get a value from the database
sub getkey
{
	my $self = shift;
	my $key = uc shift;
	my $value;

	# massage the key
	$key =~ s/[\@\$\&\%\*]+//g;
	$key =~ s/^[\.\/]+//g;
	
	# make sure we are open
	$self->open;
	if ($self->{localcmd}) {
		my $dxchan = $main::me;
		$dxchan->{remotecmd} = 1; # for the benefit of any command that needs to know
		my $oldpriv = $dxchan->{priv};
		$dxchan->{priv} = 0;
		my @in = (DXCommandmode::run_cmd($dxchan, "$self->{localcmd} $key"));
		$dxchan->{priv} = $oldpriv;
		delete $dxchan->{remotecmd};
		return @in ? join("\n", @in) : undef;
	} elsif ($self->{db}) {
		my $s = $self->{db}->get($key, $value);
		return $s ? undef : $value;
	}
	return undef;
}

# put a value to the database
sub putkey
{
	my $self = shift;
	my $key = uc shift;
	my $value = shift;

	# make sure we are open
	$self->open;
	if ($self->{db}) {
		my $s = $self->{db}->put($key, $value);
		return $s ? undef : 1;
	}
	return undef;
}

# create a new database params: <name> [<remote node call>]
sub new
{
	my $self = bless {};
	my $name = shift;
	my $remote = shift;
	my $chain = shift;
	my $cmd = shift;
	
	$self->{name} = lc $name;
	$self->{remote} = uc $remote if $remote;
	$self->{chain} = $chain if $chain && ref $chain;
	$self->{accesst} = $self->{createt} = $self->{lastt} = $main::systime;
	$self->{localcmd} = lc $cmd if $cmd;
	
	$avail{$self->{name}} = $self;
	mkdir $dbbase, 02775 unless -e $dbbase;
	save();
	return $self;
}

# delete a database
sub delete
{
	my $self = shift;
	$self->close;
	unlink "$dbbase/$self->{name}";
	delete $avail{$self->{name}};
	save();
}

#
# process intermediate lines for an update
# NOTE THAT THIS WILL BE CALLED FROM DXCommandmode and the
# object will be a DXChannel (actually DXCommandmode)
#
sub normal
{
	
}

#
# periodic maintenance
#
# just close any things that haven't been accessed for the default
# time 
#
#
sub process
{
	if ($main::systime - $lastprocesstime >= 60) {
		if (%avail) {
			for (values %avail) {
				if ($main::systime - $_->{accesst} > $opentime) {
					$_->close;
				}
			}
		}
		$lastprocesstime = $main::systime;
	}
}

sub handle_37
{		

}

sub handle_44
{	
	my $self = shift;

	# incoming DB Request
	my @in = DXCommandmode::run_cmd($self, "dbshow $_[4] $_[5]");
	sendremote($self, $_[2], $_[3], @in);
}

sub handle_45
{		
	my $self = shift;

	# incoming DB Information
	my $n = getstream($_[3]);
	if ($n) {
		my $mchan = DXChannel::get($n->{call});
		$mchan->send($_[2] . ":$_[4]") if $mchan;
	}
}

sub handle_46
{		
	my $self = shift;

	# incoming DB Complete
	delstream($_[3]);
}

sub handle_47
{
}

sub handle_48
{
}

# send back a trache of data to the remote
# remember $dxchan is a dxchannel
sub sendremote
{
	my $dxchan = shift;
	my $tonode = shift;
	my $stream = shift;

	for (@_) {
		$dxchan->send(DXProt::pc45($main::mycall, $tonode, $stream, $_));
	}
	$dxchan->send(DXProt::pc46($main::mycall, $tonode, $stream));
}

# print a value from the db reference
sub print
{
	my $self = shift;
	my $s = shift;
	return $self->{$s} ? $self->{$s} : undef; 
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

1;
