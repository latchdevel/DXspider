#
# set beeps
#
# Copyright (c) 1998 - Dirk Koopman G1TLH
#
# $Id$
#
my $self = shift;
$self->user->wantbeep(0);
$self->beep(0);
return (1, $self->msg('beepoff'));
