#
# This module is part of the new protocal mode for a dx cluster
#
# This module handles the initialisation between two nodes
#
# Copyright (c) 2003 Dirk Koopman G1TLH
#
# $Id$
# 

package QXI;

use strict;

use vars qw(@ISA $VERSION $BRANCH);
@ISA = qw(QXProt);

$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /\d+\.\d+\.(\d+)\.(\d+)/,(0,0));
$main::build += $VERSION;
$main::branch += $BRANCH;


sub handle
{
	my ($self, $to, $from, $msgid, $line) = @_;
	
	my @f = split /\^/, $line;
	if ($self->user->passphrase && @f > 3) {
		my $inv = Verify->new($f[3]);
		unless ($inv->verify($f[4], $main::me->user->passphrase, $main::mycall, $self->call)) {
			$self->sendnow('D','Sorry...');
			$self->disconnect;
		}
		$self->{verified} = 1;
	} else {
		$self->{verified} = 0;
	}
	if ($self->{outbound}) {
		$self->send($self->QXI::gen);
	} 
	if ($self->{sort} ne 'S' && $f[0] eq 'DXSpider') {
		$self->{user}->{sort} = $self->{sort} = 'S';
		$self->{user}->{priv} = $self->{priv} = 1 unless $self->{priv};
	}
	$self->{version} = $f[1];
	$self->{build} = $f[2];
	$self->state('init1');
	$self->{lastping} = 0;
}

sub gen
{
	my $self = shift;
	my @out = ('I', $self->call, "DXSpider", ($main::version + 53) * 100, $main::build);
	if (my $pass = $self->user->passphrase) {
		my $inp = Verify->new;
		push @out, $inp->challenge, $inp->response($pass, $self->call, $main::mycall);
	}
	return $self->frame(@out);
}

1;
