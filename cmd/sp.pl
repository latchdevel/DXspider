#
# synonym for send or SP send private
#
# Copyright (c) 1998 Dirk Koopman G1TLH
#
# $Id$
#

my $ref = DXCommandmode::find_cmd_ref('send');
return ( &{$ref}(@_) ) if $ref;
return (0,());
