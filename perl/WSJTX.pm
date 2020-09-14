#
# WSJTX logging and control protocol decoder etc
#
#

package WSJTX;

use strict;
use warnings;
use 5.10.1;

use JSON;
use DXDebug;

my $json;

our %spec = (
			 '0' => [
					 ['type', 'int32'],
					 ['id', 'utf'],
					 ['schema', 'int32'],
					 ['version', 'utf'],
					 ['revision', 'utf'],
					],
			 '1' => [
					 ['type', 'int32'],
					 ['id', 'utf'],
					 ['qrg', 'int64', '_myqrg'],
					 ['mode', 'utf'],
					 ['dxcall', 'utf'],
					 ['report', 'utf'],
					 ['txmode', 'utf'],
					 ['txenabled', 'bool'],
					 ['txing', 'bool'],
					 ['decoding', 'bool'],
					 ['rxdf', 'int32'],
					 ['txdf', 'int32'],
					 ['mycall', 'utf', '_mycall'],
					 ['mygrid', 'utf', '_mygrid'],
					 ['dxgrid', 'utf'],
					 ['txwd', 'bool'],
					 ['submode', 'utf'],
					 ['fastmode', 'bool'],
					 ['som', 'int8', \&_som],
					 ['qrgtol', 'int32'],
					 ['trperiod', 'int32'],
					 ['confname', 'utf'],
					],
			 '2' => [
					 ['type', 'int32'],
					 ['id', 'utf'],
					 ['new', 'bool'],
					 ['tms', 'int32'],
					 ['snr', 'int32'],
					 ['deltat', 'float'],
					 ['deltaqrg', 'int32'],
					 ['mode', 'utf'],
					 ['msg', 'utf'],
					 ['lowconf', 'bool'],
					 ['offair', 'bool'],
					],
			 '3' => [
					 ['type', 'int32'],
					 ['id', 'utf'],
					 ['window', 'int8'],
					],
			 '4' => [
					 ['type', 'int32'],
					 ['id', 'utf'],
					 ['tms', 'int32'],
					 ['snr', 'int32'],
					 ['deltat', 'float'],
					 ['deltaqrg', 'int32'],
					 ['mode', 'utf'],
					 ['msg', 'utf'],
					 ['lowconf', 'bool'],
					 ['modifiers', 'int8'],
					],
			 '5' => [
					 ['type', 'int32'],
					 ['id', 'utf'],
					 ['toff', 'qdate'],
					 ['dxcall', 'utf'],
					 ['dxgrid', 'utf'],
					 ['qrg', 'int64'],
					 ['mode', 'utf'],
					 ['repsent', 'utf'],
					 ['reprcvd', 'utf'],
					 ['txpower', 'utf'],
					 ['comment', 'utf'],
					 ['name', 'utf'],
					 ['ton', 'qdate'],
					 ['opcall', 'utf'],
					 ['mycall', 'utf'],
					 ['mysent', 'utf'],
					 ['xchgsent', 'utf'],
					 ['reprcvd', 'utf'],
					],
			 '6' => [
					 ['type', 'int32'],
					 ['id', 'utf'],
					],
			 '7' => [
					 ['type', 'int32'],
					 ['id', 'utf'],
					],
			 '8' => [
					 ['type', 'int32'],
					 ['id', 'utf'],
					 ['autotx', 'bool'],
					],
			 '9' => [
					 ['type', 'int32'],
					 ['id', 'utf'],
					 ['txt', 'utf'],
					 ['send', 'bool'],
					],
			 '10' => [
					  ['type', 'int32'],
					  ['id', 'utf'],
					  ['new', 'bool'],
					  ['tms', 'int32'],
					  ['snr', 'int32'],
					  ['deltat', 'float'],
					  ['qrg', 'int64'],
					  ['drift', 'int32'],
					  ['call', 'utf'],
					  ['grid', 'utf'],
					  ['power', 'int32'],
					  ['offair', 'bool'],
					 ],
			 '11' => [
					 ['type', 'int32'],
					 ['id', 'utf'],
					 ['grid', 'utf'],
					],
			 '12' => [
					 ['type', 'int32'],
					 ['id', 'utf'],
					 ['adif', 'utf'],
					],
			 
			);

sub new
{
	my $name = shift;
	my $args =  ref $_[0] ? $_[0] : {@_};

	$json = JSON->new->canonical unless $json;

	my $self = bless {}, $name;
	if (exists $args->{handle}) {
		my $v = $args->{handle};
		for (split ',', $v) {
			$self->{"h_$_"} = 1;
		}
	}
	return $self;
	
}

sub handle
{
	my ($self, $handle, $data, $origin) = @_;

	my $lth = length $data;
	dbgdump('udp', "UDP IN lth: $lth", $data);

	my ($magic, $schema, $type) = eval {unpack 'N N N', $data};
	return 0 unless $magic == 0xadbccbda && $schema >= 0 && $schema <= 3 && $spec{$type};
	my $out = $self->unpack($data, $spec{$type}, $origin);
	dbg($out) if $out && $type != 0;
	
	return $out;
}

use constant NAME => 0;
use constant SORT => 1;
use constant FUNC => 2;
use constant LASTTIME => 0;
use constant MYCALL => 1;
use constant MYGRID => 2;
use constant MYQRG => 3;

sub unpack
{
	my $self = shift;
	my $data = shift;
	my $spec = shift;
	my $ip = shift;

	my $now = time;
	my $mycall;
	my $mygrid;
	my $myqrg;
		
	if ($ip) {
		my $cr = $self->{CR}->{$ip};
		if ($cr) {
			$mycall = $cr->[MYCALL];
			$mygrid = $cr->[MYGRID];
			$myqrg = $cr->[MYQRG];
			$cr->[LASTTIME] = $now;
		}
		$self->{ip} = $ip
	} else {
		delete $self->{ip};
	}
	
	my $pos = $self->{unpackpos} || 8;
	my $out = $pos ? '{' : '';

	foreach my $r (@$spec) {
		my $v = 'NULL';
		my $l;
		my $alpha;

		last if $pos >= length $data;
		
		if ($r->[SORT] eq 'int32') {
			$l = 4;
			($v) = unpack 'l>', substr $data, $pos, $l;
		} elsif ($r->[SORT] eq 'int64') {
			$l = 8;
			($v) = unpack 'Q>', substr $data, $pos, $l;
		} elsif ($r->[SORT] eq 'int8') {
			$l = 1;
			($v) = unpack 'c', substr $data, $pos, $l;
			
		} elsif ($r->[SORT] eq 'bool') {
			$l = 1;
			($v) = unpack 'c', substr $data, $pos, $l;
			$v += 0;
		} elsif ($r->[SORT] eq 'float') {
			$l = 8;
			($v) = unpack 'd>', substr $data, $pos, $l;
			$v = sprintf '%.3f', $v;
			$v += 0;
		} elsif ($r->[SORT] eq 'utf') {
			$l = 4;
			($v) = unpack 'l>', substr $data, $pos, 4;
			if ($v > 0) {
				($v) = unpack "a$v", substr $data, $pos+4;
				$l += length $v;
				++$alpha;
			} else {
				$pos += 4;
				next;			# null alpha field
			} 
		}

		$out .= qq{"$r->[NAME]":};
		if ($r->[FUNC]) {
			no strict 'refs';
			($v, $alpha) = $r->[FUNC]($self, $v);
		}
		$out .= $alpha ? qq{"$v"} : $v;
		$out .= ',';
		$pos += $l;
	}

	return undef unless $mycall;
	
	$out .= qq{"ocall":"$mycall",} if $mycall;
	$out .= qq{"ogrid":"$mygrid",} if $mygrid;
	$out .= qq{"oqrg":"$myqrg",} if $myqrg;
#	$out .= qq{"oip":"$ip",} if $ip;

	$out =~ s/,$//;
	$out .= '}';
	
	delete $self->{unpackpos};

	return $out;
}

sub finish
{

}

sub per_sec
{
	
}

sub per_minute
{

}

sub _som
{
	my $self = shift;
	
	my @s = qw{NONE NA-VHF EU-VHF FIELD-DAY RTTY-RU WW-DIGI FOX HOUND};
	my $v = $s[shift];
	$v ||= 'UNKNOWN';
	return ($v, 1);
}

sub _mycall
{
	my $self = shift;
	my $v = shift;
	my $ip = $self->{ip};
	my $cr = $self->{CR}->{$ip} ||= [];
	$v = $cr->[MYCALL] //= $v;
	return ($v, 1); 
}

sub _mygrid
{
	my $self = shift;
	my $v = shift;
	my $ip = $self->{ip};
	my $cr = $self->{CR}->{$ip} ||= [];
	$v = $cr->[MYGRID] //= $v;
	return ($v, 1); 
}

sub _myqrg
{
	my $self = shift;
	my $v = shift;
	my $ip = $self->{ip};
	my $cr = $self->{CR}->{$ip} ||= [];
	$v = $cr->[MYQRG] = $v;
	return ($v, 1); 
}

1;
