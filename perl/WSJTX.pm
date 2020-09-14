#
# WSJTX logging and control protocol decoder etc
#
#

package WSJTX;

use strict;
use warnings;
use 5.22.1;

use JSON;
use DXDebug;

my $json;

our %specs = (
			  'head' => [
						 ['magic', 'int32'],
						 ['proto', 'int32'],
						],
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
					  ['qrg', 'int64'],
					  ['mode', 'utf'],
					  ['dxcall', 'utf'],
					  ['report', 'utf'],
					  ['txmode', 'utf'],
					  ['txenabled', 'bool'],
					  ['txing', 'bool'],
					  ['decoding', 'bool'],
					  ['rxdf', 'int32'],
					  ['txdf', 'int32'],
					  ['mycall', 'utf'],
					  ['mygrid', 'utf'],
					  ['dxgrid', 'utf'],
					  ['txwd', 'bool'],
					  ['submode', 'utf'],
					  ['fastmode', 'bool'],
					  ['som', 'int8'],
					  ['qrgtol', 'int32'],
					  ['trperiod', 'int32'],
					  ['confname', 'utf'],
					 ],
			  '2' => [
					  ['type', 'int32'],
					  ['id', 'utf'],
					  ['new', 'bool'],
					  ['t', 'int32'],
					  ['snr', 'int32'],
					  ['deltat', 'float'],
					  ['deltaqrg', 'int32'],
					  ['mode', 'utf'],
					  ['msg', 'utf'],
					  ['lowconf', 'bool'],
					  ['offair', 'bool'],
					 ],
			  '5' => [
					  ['type', 'int32'],
					  ['id', 'utf'],
					  ['toff', 'qtime'],
					  ['dxcall', 'utf'],
					  ['dxgrid', 'utf'],
					  ['qrg', 'int64'],
					  ['mode', 'utf'],
					  ['repsent', 'utf'],
					  ['reprcvd', 'utf'],
					  ['txpower', 'utf'],
					  ['comment', 'utf'],
					  ['name', 'utf'],
					  ['ton', 'qtime'],
					  ['opcall', 'utf'],
					  ['mycall', 'utf'],
					  ['mysent', 'utf'],
					  ['xchgsent', 'utf'],
					  ['reprcvd', 'utf'],
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
	my ($self, $handle, $data) = @_;

	my $lth = length $data;
	dbgdump('udp', "UDP IN lth: $lth", $data);

	my ($magic, $schema, $type) = eval {unpack 'N N N', $data};
	return 0 unless $magic == 0xadbccbda && $schema >= 0 && $schema <= 3 && $type >= 0  && $type <= 32; # 32 to allow for expansion

	no strict 'refs';
	my $h = "decode$type";
	if ($self->can($h)) {
		my $a = unpack "H*", $data;
		$a =~ s/f{8}/00000000/g;
		$data = pack 'H*', $a;
		dbgdump('udp', "UDP process lth: $lth", $data);
		$self->$h($type, substr($data, 12)) if $self->{"h_$type"};
	} else {
		dbg("decode $type not implemented");
	}

	
	return 1;
	
}

sub decode0
{
	my ($self, $type, $data) = @_;

	my %r;
	$r{type} = $type;

	($r{id}, $r{schema}, $r{version}, $r{revision}) = eval {unpack 'l>/a N l>/a l>/a', $data};
	if ($@) {
		dbg($@);
	} else {
		my $j = $json->encode(\%r);
		dbg($j);
	}

}

sub decode1
{
	my ($self, $type, $data) = @_;

	my %r;
	$r{type} = $type;
	
	(
	 $r{id}, $r{qrg}, $r{mode}, $r{dxcall}, $r{report}, $r{txmode},
	 $r{txenabled}, $r{txing}, $r{decoding}, $r{rxdf}, $r{txdf},
	 $r{decall}, $r{degrid}, $r{dxgrid}, $r{txwatch}, $r{som},
	 $r{fast}, $r{qrgtol}, $r{trperiod}, $r{confname}
	 
	) = eval {unpack 'l>/a Q> l>/a l>/a l>/a l>/a C C C l> l> l>/a l>/a l>/a C l>/a c l> l> l>/a', $data};
	if ($@) {
		dbg($@);
	} else {
		my $j = $json->encode(\%r);
		dbg($j);
	}
}

sub decode2
{
	my ($self, $type, $data) = @_;

	my %r;
	$r{type} = $type;
	
	(
	 $r{id}, $r{new}, $r{tms}, $r{snr}, $r{deltat}, $r{deltaqrg}, $r{mode}, $r{msg}, $r{lowconf}, $r{offair}
	)  = eval {unpack 'l>/a C N l> d> N l>/a l>/a C C ', $data};
	if ($@) {
		dbg($@);
	} else {
		my $j = $json->encode(\%r);
		dbg($j);
	}
}

use constant NAME => 0;
use constant SORT => 1;
use constant FUNCTION => 3;

sub unpack
{
	my $self = shift;
	my $data = shift;
	my $spec = shift;
	my $end = shift;

	my $pos = $self->{unpackpos} || 0;
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
				($v) = unpack "a$v", substr $data, $pos;
				$l += length $v;
				++$alpha;
			} else {
				next;			# null alpha field
			} 
		}

		$out .= qq{"$r->[NAME]":};
		$out .= $alpha ? qq{"$v"} : $v;
		$out .= ',';
		$pos += $l;
	}

	if ($end) {
		$out =~ s/,$//;
		$out .= '}';
		delete $self->{unpackpos};
	} else {
		$self->{unpackpos} = $pos;
	}
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


1;
