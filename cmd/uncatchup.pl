#
# uncatchup some or all of the non-private messages for a node.
#
# in other words mark  messages as NOT being already received
# by this node.
#
# $Id$
#
# Copyright (c) 1999 Dirk Koopman G1TLH
#

my ($self, $line) = @_;
my @f = split /\s+/, $line;
my $call = uc shift @f;
my @out;


return (1, @out);
