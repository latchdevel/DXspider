
#
# This module is part of the new protocal mode for a dx cluster
#
# This module handles the Routing message between nodes
#
# Copyright (c) 2003 Dirk Koopman G1TLH
#
# $Id$
# 

package QXR;

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
 
}

sub gen
{
	my $self = shift;
	my @out = ('R', $self->call, "DXSpider", ($main::version + 53) * 100, $main::build);
	if (my $pass = $self->user->passphrase) {
		my $inp = Verify->new;
		push @out, $inp->challenge, $inp->response($pass, $self->call, $main::mycall);
	}
	return $self->frame(@out);
}

1;

sub gen2
{
	my $self = shift;
	
	my $node = shift;
	my $sort = shift;
	my @out;
	my $dxchan;
	
	while (@_) {
		my $str = '';
		for (; @_ && length $str <= 230;) {
			my $ref = shift;
			my $call = $ref->call;
			my $flag = 0;
			
			$flag += 1 if $ref->here;
			$flag += 2 if $ref->conf;
			if ($ref->is_node) {
				my $ping = int($ref->pingave * 10);
				$str .= "^N$flag$call,$ping";
				my $v = $ref->build || $ref->version;
				$str .= ",$v" if defined $v;
			} else {
				$str .= "^U$flag$call";
			}
		}
		push @out, $str if $str;
	}
	my $n = @out;
	my $h = get_hops(90);
	@out = map { sprintf "PC90^%s^%X^%s%d%s^%s^", $node->call, $main::systime, $sort, --$n, $_, $h } @out;
	return @out;
}
