#
# XML (R)Cmd handler
#
#
#
# Copyright (c) Dirk Koopman, G1TLH
#

use strict;

package DXXml::Cmd;

use DXDebug;
use DXProt;
use IsoTime;
use Investigate;
use DXXml::Text;
use DXLog;

use vars qw(@ISA);
@ISA = qw(DXXml);

sub handle_input
{
	my $self = shift;
	my $dxchan = shift;

	if ($self->{to} eq $main::mycall) {
		my @in;
		
		my $cmd = $self->{content};
		
		if ($self->{u} && $self->{u} eq $dxchan->call) {	# online user or node
			@in = (DXCommandmode::run_cmd($dxchan, $cmd));
		} else {
			# remote command
			my $ref = DXUser->get_current($self->{o});
			my $cref = Route::Node::get($self->{o});
			my $answer;
			
			if ($cmd !~ /^\s*rcmd/i && $cref && $ref && $cref->call eq $ref->homenode) { # not allowed to relay RCMDS!
				$self->{remotecmd} = 1; # for the benefit of any command that needs to know
				my $oldpriv = $dxchan->{priv};
				$dxchan->{priv} = $ref->{priv}; # assume the user's privilege level
				@in = (DXCommandmode::run_cmd($dxchan, $cmd));
				$dxchan->{priv} = $oldpriv;
				delete $dxchan->{remotecmd};
				$answer = "success";
			} else {
				$answer = "denied";
			}
			Log('rcmd', 'in', $ref->{priv}, $self->{o}, "$self->{content}($answer)");
		}
		my $rep = DXXml::Text->new(u=>$self->{u}, to=>$self->{o}, content=>join('%0A', map {"$main::mycall:$_"} @in));
		$rep->route($main::me); # because it's coming from me!
	} else {
		$self->route($dxchan);
	}
}

sub topcxx
{
	my $self = shift;

	my $ref = DXUser->get_current($self->{to});
	my $s;
	
	if ($ref && $ref->is_clx && $self->{u}) {
		$s = DXProt::pc84(($self->{o} || $main::mycall), $self->{to}, $self->{u}, $self->{content});
	} else {
		$s = DXProt::pc34(($self->{o} || $main::mycall), $self->{to}, $self->{content});
	}
	return $self->{'-pcxx'} = $s;
}

1;
