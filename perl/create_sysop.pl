#!/usr/bin/env perl
#
# create a NEW user database and the sysop record
#
# WARNING - running this will destroy any existing user database
#
# Copyright (c) 1998 Dirk Koopman G1TLH
#
#
# 

# make sure that modules are searched in the order local then perl
BEGIN {
	# root of directory tree for this system
	$root = "/spider"; 
	$root = $ENV{'DXSPIDER_ROOT'} if $ENV{'DXSPIDER_ROOT'};

	unshift @INC, "$root/perl"; # this IS the right way round!
	unshift @INC, "$root/local";
}

use DXVars;
use SysVar;
use DXUser;
use DXUtil;

sub delete_it
{
	DXUser::del_file();
}

sub create_it
{
	my $ref = DXUser::get(uc $mycall);
	$ref->del() if $ref;
	
	my $self = DXUser->new(uc $mycall);
	$self->{alias} = uc $myalias;
	$self->{name} = $myname;
	$self->{qth} = $myqth;
	$self->{qra} = uc $mylocator;
	$self->{lat} = $mylatitude;
	$self->{long} = $mylongitude;
	$self->{email} = $myemail;
	$self->{bbsaddr} = $mybbsaddr;
	$self->{homenode} = uc $mycall;
	$self->{sort} = 'S';		# C - Console user, S - Spider cluster, A - AK1A, U - User, B - BBS
	$self->{priv} = 9;			# 0 - 9 - with 9 being the highest
	$self->{lastin} = 0;
	$self->{dxok} = 1;
	$self->{annok} = 1;

	# write it away
	$self->put();

	# now do one for the alias
	$ref = DXUser::get(uc $myalias);
	$ref->del() if $ref;

	$self = DXUser->new(uc $myalias);
	$self->{name} = $myname;
	$self->{qth} = $myqth;
	$self->{qra} = uc $mylocator;
	$self->{lat} = $mylatitude;
	$self->{long} = $mylongitude;
	$self->{email} = $myemail;
	$self->{bbsaddr} = $mybbsaddr;
	$self->{homenode} = uc $mycall;
	$self->{sort} = 'U';		# C - Console user, S - Spider cluster, A - AK1A, U - User, B - BBS
	$self->{priv} = 9;			# 0 - 9 - with 9 being the highest
	$self->{lastin} = 0;
	$self->{dxok} = 1;
	$self->{annok} = 1;
	$self->{lang} = 'en';
	$self->{group} = [qw(local #9000)];
  
	# write it away
	$self->put();

}

die "\$myalias \& \$mycall are the same ($mycall)!, they must be different (hint: make \$mycall = '${mycall}-2';).\n" if $mycall eq $myalias;

$lockfn = "$main::local_data/cluster.lck";       # lock file name (now in local data)
if (-e $lockfn) {
	open(CLLOCK, "$lockfn") or die "Can't open Lockfile ($lockfn) $!";
	my $pid = <CLLOCK>;
	chomp $pid;
	die "Sorry, Lockfile ($lockfn) and process $pid exist, a cluster is running\n" if kill 0, $pid;
	close CLLOCK;
}

$DXUser::v4 = 1;

if (-e localdata("users.v4")) {
	print "Do you wish to destroy your user database (THINK!!!) [y/N]: ";
	$ans = <STDIN>;
	if ($ans =~ /^[Yy]/) {
		delete_it();
		DXUser::init(4);
		create_it();
	} else {
		print "Do you wish to reset your cluster and sysop information? [y/N]: ";
		$ans = <STDIN>;
		if ($ans =~ /^[Yy]/) {
			DXUser::init(4);
			create_it();
		}
	}
  
} else {
	DXUser::init(4);
	create_it();
}
DXUser::finish();
exit(0);

