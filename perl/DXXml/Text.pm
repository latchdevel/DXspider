#
# XML Text handler
#
#
#
# Copyright (c) Dirk Koopman, G1TLH
#

use strict;

package DXXml::Text;

use DXDebug;
use DXProt;
use DXLog;

use vars qw(@ISA);
@ISA = qw(DXXml);

sub handle_input
{
	my $self = shift;
	my $dxchan = shift;

	if ($self->{to} eq $main::mycall) {
		my $tochan = DXChannel::get($self->{u} || $main::myalias);
		if ($tochan) {
			$tochan->send($self->tocmd);
		} else {
			dbg("no user or $main::myalias not online") if isdbg('chanerr');
		}
	} else {	
		$self->route($dxchan);
	}
}

sub topcxx
{
	my $self = shift;
	my $dxchan = shift;
	my @out;

	my $ref = DXUser::get_current($self->{to});
	for (split /(?:%0D)?\%0A/, $self->{content}) {
		my $line = $_;
		$line =~ s/\s*$//;
		Log('rcmd', 'out', $self->{to}, $line);
		if ($self->{u} && $dxchan->is_clx && $ref->is_clx) {
			push @out, DXProt::pc85($main::mycall, $self->{to}, $self->{u}, "$main::mycall:$line");
		} else {
			push @out, DXProt::pc35($main::mycall, $self->{to}, "$main::mycall:$line");
		}
	}

	return $self->{'-pcxx'} = \@out;
}

sub tocmd
{
	my $self = shift;

	my @out = split /(?:%0D)?\%0A/, $self->{content};
	return $self->{-cmd} = \@out;
}

1;
