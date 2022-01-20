#
# IP Address block list / checker
#
# This is a DXSpider compatible, optional skin over Net::CIDR::Lite
# If Net::CIDR::Lite is not present, then a find will always returns 0
#

package DXCIDR;

use strict;
use warnings;
use 5.16.1;
use DXVars;
use DXDebug;
use DXUtil;
use DXLog;
use IO::File;
use File::Copy;

our $active = 0;
our $badipfn = "badip";
my $ipv4;
my $ipv6;
my $count4 = 0;
my $count6 = 0;

# load the badip file
sub load
{
	if ($active) {
		$count4 = _get($ipv4, 4);
		$count6 = _get($ipv6, 6);
	}
	LogDbg('DXProt', "DXCIDR: loaded $count4 IPV4 addresses and $count6 IPV6 addresses");
	return $count4 + $count6;
}

sub _fn
{
	return localdata($badipfn) . "$_[0]";
}

sub _get
{
	my $list = shift;
	my $sort = shift;
	my $fn = _fn($sort);
	my $fh = IO::File->new($fn);
	my $count = 0;
	
	if ($fh) {
		while (<$fh>) {
			chomp;
			next if /^\s*\#/;
			$list->add($_);
			++$count;
		}
		$fh->close;
		$list->clean if $count;
	} elsif (-r $fn) {
		LogDbg('err', "DXCIDR: $fn not found ($!)");
	}
	return $count;
}

sub _put
{
	my $list = shift;
	my $sort = shift;
	my $fn = _fn($sort);
	my $r = rand;
	my $fh = IO::File->new (">$fn.$r");
	if ($fh) {
		for ($list->list) {
			$fh->print("$_\n");
		}
		move "$fn.$r", $fn;
	} else {
		LogDbg('err', "DXCIDR: cannot write $fn.$r $!");
	}
}

sub add
{
	for (@_) {
		# protect against stupid or malicious
		next if /^127\./;
		next if /^::1$/;
		if (/\./) {
			$ipv4->add($_);
			++$count4;
			LogDbg('DXProt', "DXCIDR: Added IPV4 $_ address");
		} else {
			$ipv6->add($_);
			++$count6;
			LogDbg('DXProt', "DXCIDR: Added IPV6 $_ address");
		}
	}
	if ($ipv4 && $count4) {
		$ipv4->prep_find;
		_put($ipv4, 4);
	}
	if ($ipv6 && $count6) {
		$ipv6->prep_find;
		_put($ipv6, 6);
	}
}

sub save
{
	return 0 unless $active;
	my $list = $ipv4->list;
	_put($list, 4) if $list;
	$list = $ipv6->list;
	_put($list, 6) if $list;
}

sub list
{
	my @out;
	push @out, $ipv4->list;
	push @out, $ipv6->list;
	return (1, sort @out);
}

sub find
{
	return 0 unless $active;
	return 0 unless $_[0];
	
	if ($_[0] =~ /\./) {
		return $ipv4->find($_[0]) if $count4;
	}
	return $ipv6->find($_[0]) if $count6;
}

sub init
{
	eval { require Net::CIDR::Lite };
	if ($@) {
		LogDbg('DXProt', "DXCIDR: load (cpanm) the perl module Net::CIDR::Lite to check for bad IP addresses (or CIDR ranges)");
		return;
	}

	import Net::CIDR::Lite;

	$ipv4 = Net::CIDR::Lite->new;
	$ipv6 = Net::CIDR::Lite->new;

	load();
	$active = 1;
}



1;
