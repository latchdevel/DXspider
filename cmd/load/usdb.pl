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

my ($self, $line) = @_;
my @out;
return (1, $self->msg('e5')) if $self->priv < 9;
my $r = USDB::load($line) if $line;
USDB::init() if undef $r || $r =~ /^\d+ rec/;
return (1, @out); 
