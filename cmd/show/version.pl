#
# show the version number of the software + copyright info
#
# Copyright (c) 1998 Dirk Koopman G1TLH
#
# $Id$
#

my @out;

push @out, "DX Spider Cluster version $main::version";
push @out, "written in perl for unix";
push @out, "Copyright (c) 1998 Dirk Koopman G1TLH";

return (1, @out);
