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
#
# 

# make sure that modules are searched in the order local then perl

BEGIN {
	# root of directory tree for this system
	$root = "/spider"; 
	$root = $ENV{'DXSPIDER_ROOT'} if $ENV{'DXSPIDER_ROOT'};
        unshift @INC, "$root/perl";     # this IS the right way round!
	unshift @INC, "$root/local";
}

use DXVars;
use DXUser;

my $lockfn = "$root/local/cluster.lck";       # lock file name
if (-e $lockfn) {
	open(CLLOCK, "$lockfn") or die "Can't open Lockfile ($lockfn) $!";
	my $pid = <CLLOCK>;
	chomp $pid;
	die "Sorry, Lockfile ($lockfn) and process $pid exist, a cluster is running\n" if kill 0, $pid;
	close CLLOCK;
}

my @nodes = map { uc } @ARGV;

DXUser->init($userfn, 1);

my $count;
my $nodes;
my @ignore;
my ($action, $key, $data) = (0,0,0);
for ($action = DXUser::R_FIRST, $count = 0; !$DXUser::dbm->seq($key, $data, $action); $action = DXUser::R_NEXT) {
	if ($data =~ m{sort => '[ACRSX]'}) {
		my $user = DXUser::get($key);
		if ($user->is_node) {
			$nodes ++;
			if (grep $key eq $_, (@nodes, $mycall)) {
				push @ignore, $key;
				next;
			}
			my $priv = $user->priv;
			if ($priv > 1) {
				push @ignore, $key;
				next;
			}
			$user->priv(1) unless $priv;
			$user->lockout(1);
			$user->put;
			$count++;
		}
	}
}

print "locked out $count nodes out of $nodes\n";
print scalar @ignore, " nodes ignored (", join(',', @ignore), ")\n";
print "If there are any nodes missing on the above list then you MUST do\n";
print "a set/node (set/spider, set/clx etc) on each of them to allow them\n";
print "to connect to you or you to them\n"; 
 
DXUser->finish();
exit(0);

