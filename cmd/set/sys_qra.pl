#
# set the cluster qra locator field
#
# Copyright (c) 1998 - Dirk Koopman
#
# $Id$
#

my ($self, $line) = @_;
return (1, $self->msg('e5')) if $self->priv < 9;
return (1, run_cmd("set/qra $main::mycall"));
