#!/usr/bin/perl
#
# create a NEW user database and the sysop record
#
# WARNING - running this will destroy any existing user database
#
# Copyright (c) 1998 Dirk Koopman G1TLH
#
# $Id$
# 

# make sure that modules are searched in the order local then perl
BEGIN {
	# root of directory tree for this system
	$root = "/spider"; 
	$root = $ENV{'DXSPIDER_ROOT'} if $ENV{'DXSPIDER_ROOT'};

	unshift @INC, "$root/local";
}

use DXVars;
use DXUser;

sub delete_it
{
	DXUser->del_file($userfn);
}

sub create_it
{
	my $ref = DXUser->get($mycall);
	$ref->del() if $ref;
	
	my $self = DXUser->new($mycall);
	$self->{alias} = $myalias;
	$self->{name} = $myname;
	$self->{qth} = $myqth;
	$self->{qra} = $mylocator;
	$self->{lat} = $mylatitude;
	$self->{long} = $mylongitude;
	$self->{email} = $myemail;
	$self->{bbsaddr} = $mybbsaddr;
	$self->{homenode} = $mycall;
	$self->{sort} = 'A';		# C - Console user, S - Spider cluster, A - AK1A, U - User, B - BBS
	$self->{priv} = 9;			# 0 - 9 - with 9 being the highest
	$self->{lastin} = 0;
	$self->{dxok} = 1;
	$self->{annok} = 1;

	# write it away
	$self->close();

	# now do one for the alias
	$ref = DXUser->get($myalias);
	$ref->del() if $ref;

	$self = DXUser->new($myalias);
	$self->{name} = $myname;
	$self->{qth} = $myqth;
	$self->{qra} = $mylocator;
	$self->{lat} = $mylatitude;
	$self->{long} = $mylongitude;
	$self->{email} = $myemail;
	$self->{bbsaddr} = $mybbsaddr;
	$self->{homenode} = $mycall;
	$self->{sort} = 'U';		# C - Console user, S - Spider cluster, A - AK1A, U - User, B - BBS
	$self->{priv} = 9;			# 0 - 9 - with 9 being the highest
	$self->{lastin} = 0;
	$self->{dxok} = 1;
	$self->{annok} = 1;
	$self->{lang} = 'en';
  
	# write it away
	$self->close();

}

$lockfn = "$root/perl/cluster.lck";       # lock file name
if (-e $lockfn) {
	open(CLLOCK, "$lockfn") or die "Can't open Lockfile ($lockfn) $!";
	my $pid = <CLLOCK>;
	chomp $pid;
	die "Sorry, Lockfile ($lockfn) and process $pid exist, a cluster is running\n" if kill 0, $pid;
	close CLLOCK;
}

if (-e "$userfn") {
	print "Do you wish to destroy your user database (THINK!!!) [y/N]: ";
	$ans = <STDIN>;
	if ($ans =~ /^[Yy]/) {
		delete_it();
		DXUser->init($userfn, 1);
		create_it();
	} else {
		print "Do you wish to reset your cluster and sysop information? [y/N]: ";
		$ans = <STDIN>;
		if ($ans =~ /^[Yy]/) {
			DXUser->init($userfn, 1);
			create_it();
		}
	}
  
} else {
	DXUser->init($userfn, 1);
	create_it();
}
DXUser->finish();
exit(0);

