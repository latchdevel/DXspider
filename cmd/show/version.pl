#
# show the version number of the software + copyright info
#
# Copyright (c) 1998 Dirk Koopman G1TLH
#
# $Id$
#

my @out;
my $build = $main::version;

if (opendir(DIR, "$main::root/perl")) {
	my @d = readdir(DIR);
	closedir(DIR);
	foreach my $fn (@d) {
		if ($fn =~ /^cluster\.pl$/ || $fn =~ /\.pm$/) {
			my $f = new IO::File "$main::root/perl/$fn" or next;
			while (<$f>) {
				if (/^#\s+\$Id:\s+[\w\._]+,v\s+(\d+\.\d+)/ ) {
					$build += $1;
					last;
				}
			}
			$f->close;
		}
	}
}
push @out, "DX Spider Cluster version $main::version (build $build) on \u$^O";
push @out, "Copyright (c) 1998-2001 Dirk Koopman G1TLH";

return (1, @out);
