#
# Print n blank lines
#
# Copyright (c) 1998 Dirk Koopman G1TLH
#
# $Id$
#

my ($self, $line) = @_;
my ($lines) = $line =~ /^\s*(\d+)/;
$lines ||= 1;
my @out;
push @out, ' ' for (1..$lines);
return (1, @out);
