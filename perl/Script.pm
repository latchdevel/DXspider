#
# module to do startup script handling
#
# Copyright (c) 2001 Dirk Koopman G1TLH
#
# $Id$
#

package Script;

use strict;

use DXUtil;
use DXDebug;
use DXChannel;
use DXCommandmode;
use DXVars;
use IO::File;

use vars qw($VERSION $BRANCH);
$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /\d+\.\d+\.(\d+)\.(\d+)/,(0,0));
$main::build += $VERSION;
$main::branch += $BRANCH;

my $base = "$main::root/scripts";

sub new
{
	my $pkg = shift;
	my $script = shift;
	my $fn = "$base/$script";

	my $fh = new IO::File $fn;
	return undef unless $fh;
	my $self = bless {call => $script}, $pkg;
	my @lines;
	while (<$fh>) {
		chomp;
		push @lines, $_;
	}
	$fh->close;
	$self->{lines} = \@lines;
	return $self;
}

sub run
{
	my $self = shift;
	my $dxchan = shift;
	foreach my $l (@{$self->{lines}}) {
		unless ($l =~ /^\s*\#/ || $l =~ /^\s*$/) {
			my @out = DXCommandmode::run_cmd($dxchan, $l);
			if ($dxchan->can('send_ans')) {
				$dxchan->send_ans(@out);
			} else {
				dbg($_) for @out;
			}
			last if @out && $l =~ /^pri?v?/i;
		}
	}
}
