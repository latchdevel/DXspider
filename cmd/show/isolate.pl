#
# show/isolate
#
# show all excluded users 
#
# Copyright (c) 2000 Dirk Koopman G1TLH
#
# $Id$
#

my ($self, $line) = @_;
return (1, $self->msg('e5')) unless $self->priv >= 1;

# search thru the user for nodes
my @out = sort map { my $ref; (($ref = DXUser->get_current($_)) && $ref->isolate) ? $_ : () } DXUser::get_all_calls;
return (1, @out);
