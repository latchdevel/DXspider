#
# reload the usdb file
#
# Be warned, if this is the full database the size of your image will
# increase by at least 20Mb and all activity will stop for several
# minutes
# 
# So there.
#
# Copyright (c) 2002 Dirk Koopman G1TLH
#
# $Id$
#

my $self = shift;
my @out;
return (1, $self->msg('e5')) if $self->priv < 9;
push @out, (USDB::load());
@out = ($self->msg('ok')) unless @out;
return (1, @out); 
