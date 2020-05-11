#
# module to do startup script handling
#
# Copyright (c) 2001 Dirk Koopman G1TLH
#
#
#

package Script;

use strict;

use DXUtil;
use DXDebug;
use DXChannel;
use DXCommandmode;
use DXVars;
use IO::File;

my $base = "$main::root/scripts";

sub clean
{
	my $s = shift;
	$s =~ s/([-\w\d_]+)/$1/g;
	return $s;
}

sub new
{
	my $pkg = shift;
	my $script = clean(shift);
	my $mybase = shift || $base;
	my $fn = "$mybase/$script";

	my $self = {call => $script};
	my $fh = IO::File->new($fn);
	if ($fh) {
		$self->{fn} = $fn;
	} else {
		$fh = IO::File->new(lc $fn);
		if ($fh) {
			$self->{fn} = $fn;
		} else {
			return undef;
		}
	}
	my @lines;
	while (<$fh>) {
		chomp;
		push @lines, $_;
	}
	$fh->close;
	$self->{lines} = \@lines;
	$self->{inscript} = 1;
	return bless $self, $pkg;
}

sub run
{
	my $self = shift;
	my $dxchan = shift;
	my $return_output = shift;
	my @out;
	
	foreach my $l (@{$self->{lines}}) {
		unless ($l =~ /^\s*\#/ || $l =~ /^\s*$/) {
			$dxchan->inscript(1) if $self->{inscript};
			push @out, DXCommandmode::run_cmd($dxchan, $l);
			$dxchan->inscript(0) if $self->{inscript};
			last if @out && $l =~ /^pri?v?/i;
		}
	}
	if ($return_output) {
		return @out;
	} else {
		if ($dxchan->can('send_ans')) {
			$dxchan->send_ans(@out);
		} else {
			dbg($_) for @out;
		}
	}
	return ();
}

sub inscript
{
	my $self = shift;
	$self->{inscript} = shift if @_;
	return $self->{inscript};
}

sub store
{
	my $call = clean(lc shift);
	my @out;
	my $ref = ref $_[0] ? shift : \@_;
	my $count;
	my $fn = "$base/$call";

    rename $fn, "$fn.o" if -e $fn;
	my $f = IO::File->new(">$fn") || return undef;
	for (@$ref) {
		$f->print("$_\n");
		$count++;
	}
	$f->close;
	unlink $fn unless $count;
	return $count;
}

sub lines
{
	my $self = shift;
	return @{$self->{lines}};
}

sub erase
{
	my $self = shift;
	my $call = clean($self->{call});

	my $fn;
	my $try;

	$try = "$base/" . clean(lc $self->call);
	if (-w $try) {
		$fn = $try;
	} else {
		$try = "$base/" . clean(uc $self->call);
		if (-w $try) {
			$fn = $try;
		}
	}

	if ($fn && -w $fn) {
		unless (unlink $fn) {
			return ($self->msg('m22'. $call)); 
		}
		return ($self->msg('m20', $call));
	}
	return ($self->msg('e3', "unset/startup", $call));
}
