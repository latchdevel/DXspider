#
# show the contents of the message directory
#
# Copyright (c) Dirk Koopman G1TLH
#
# $Id$
#

my ($self, $line) = @_;
my @f = split /\s+/, $line;
my @ref = DXMsg::get_all();
my $ref;
my @out;

foreach $ref (@ref) {
  next if $self->priv < 5 && $ref->private && $ref->to ne $self->call;
  push @out, sprintf "%6d %s%s%5d %8.8s %8.8s %-6.6s %5.5s %-30.30s", 
    $ref->msgno, $ref->private ? 'p' : ' ', $ref->read ? '-' : ' ', $ref->size,
	$ref->to, $ref->from, cldate($ref->t), ztime($ref->t), $ref->subject;
}

return (1, @out);
