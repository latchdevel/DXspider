#!/usr/bin/perl
#
# remove all records with the sysop/cluster callsign and recreate
# it from the information contained in DXVars
#
# WARNING - this must be run when the cluster.pl is down!
#
# This WILL NOT delete an old sysop call if you are simply
# changing the callsign.
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

sub create_it
{
	my $ref;
	
	while ($ref = DXUser->get($mycall)) {
		print "old call $mycall deleted\n";
		$ref->del();
	}
	
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
	$self->{sort} = 'S';		# C - Console user, S - Spider cluster, A - AK1A, U - User, B - BBS
	$self->{priv} = 9;			# 0 - 9 - with 9 being the highest
	$self->{lastin} = 0;
	$self->{dxok} = 1;
	$self->{annok} = 1;

	# write it away
	$self->close();
	print "new call $mycall added\n";

	# now do one for the alias
	while ($ref = DXUser->get($myalias)) {
		print "old call $myalias deleted\n";
		$ref->del();
	}

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
	print "new call $myalias added\n";

}

$lockfn = "$root/perl/cluster.lock";       # lock file name
if (-e $lockfn) {
	open(CLLOCK, "$lockfn") or die "Can't open Lockfile ($lockfn) $!";
	my $pid = <CLLOCK>;
	chomp $pid;
	die "Sorry, Lockfile ($lockfn) and process $pid exist, a cluster is running\n" if kill 0, $pid;
	close CLLOCK;
}

DXUser->init($userfn, 1);
create_it();
DXUser->finish();
print "Update of $myalias on cluster $mycall successful\n";
exit(0);

