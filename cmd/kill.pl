#
# kill or delete a message
#
# Copyright (c) Dirk Koopman G1TLH
#
# $Id$
#

use strict;

my ($self, $line) = @_;
my @f = split /\s+/, $line;
my $msgno;
my @out;
my @body;
my $ref;
my @refs;
my $call = $self->call;
my $full;

# $DB::single = 1;

while (@f) {
	my $f = shift @f;
	if ($f =~ /^fu/io) {
		return (1, $self->msg('e5')) if $self->priv < 5;
		$full = 1;
	} elsif ($f =~ /^\d+$/o) {
		$ref = DXMsg::get($f);
		if (!$ref) {
			push @out, "Msg $f not found";
			next;
		}
		if ($self->priv < 5 && $ref->to ne $call && $ref->from ne $call) {
			push @out, "Msg $f not available";
			next;
		} 
		push @refs, $ref;
	} elsif ($f =~ /(\d+)-(\d+)/) {
		my $from = $1;
		my $to = $2;
		@refs = grep { !($self->priv < 5 && $_->to ne $call && $_->from ne $call) } DXMsg::get_all() unless @refs;
		@refs = grep { $_->msgno >= $from && $_->msgno < $to } @refs;
	} elsif ($f =~ /^fr/io) {
		$f = shift @f;
		if ($f) {
			$f = shellregex($f);
			@refs = grep { !($self->priv < 5 && $_->to ne $call && $_->from ne $call) } DXMsg::get_all() unless @refs;
			@refs = grep { $_->from =~ m{$f}i } @refs;
		}
	} elsif ($f =~ /^to/io) {
		$f = shift @f;
		if ($f) {
			$f = shellregex($f);
			@refs = grep { !($self->priv < 5 && $_->to ne $call && $_->from ne $call) } DXMsg::get_all() unless @refs;
			@refs = grep { $_->to =~ m{$f}i } @refs;
		}
	} else {
		push @out, "invalid argument '$f'";
		return (1, @out);
	}
}

foreach $ref ( @refs) {
	Log('msg', "Message $ref->{msgno} from $ref->{from} to $ref->{to} deleted by $call");
	if ($full) {
		DXProt::broadcast_all_ak1a(DXProt::pc49($self->call, $ref->{subject}), $DXProt::me);
	}
	$ref->del_msg;
	push @out, "Message $ref->{msgno} deleted";
}

return (1, @out);
