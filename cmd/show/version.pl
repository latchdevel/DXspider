#
# show the version number of the software + copyright info
#
# Copyright (c) 1998 Dirk Koopman G1TLH
#
#
#

my @out;
my ($year) = (gmtime($main::systime))[5];
$year += 1900;
push @out, "DX Spider Cluster version $main::version (build $main::subversion.$main::build git: $main::gitversion) on \u$^O";
push @out, "Copyright (c) 1998-$year Dirk Koopman G1TLH";

return (1, @out);
