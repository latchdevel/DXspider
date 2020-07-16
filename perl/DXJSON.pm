#
# A light shim over JSON for DXSpider general purpose serialising
#
# Copyright (c) 2020 Dirk Koopman, G1TLH
#

package DXJSON;

use strict;
use warnings;

use JSON;
use Data::Structure::Util qw(unbless);
use DXDebug;
use DXUtil;

our @ISA = qw(JSON);

sub new
{
	return shift->SUPER::new()->canonical(1);
}

sub encode
{
	my $json = shift;
	my $ref = shift;
	my $name = ref $ref;
	
	unbless($ref) if $name && $name ne 'HASH';
	my $s;
	
	eval {$s = $json->SUPER::encode($ref) };
	if ($s && !$@) {
		bless $ref, $name if $name && $name ne 'HASH';
		return $s;
	}
	else {
		$s = dd($ref);
		dbg "DXJSON::encode '$s' - $@";
	}
}

sub decode
{
	my $json = shift;
	my $s = shift;
	my $name = shift;
	
	my $ref;
	eval { $ref = $json->SUPER::decode($s) };
	if ($ref && !$@) {
		return bless $ref, $name if $name;
		return $ref;
	}
	else {
		dbg "DXJSON::decode '$s' - $@";
	}
	return undef;
}

1;
