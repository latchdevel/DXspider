#!/usr/bin/perl
#
# Export the user file in a form that can be directly imported
# back with a do statement
#

require 5.004;

# search local then perl directories
BEGIN {
	# root of directory tree for this system
	$root = "/spider"; 
	$root = $ENV{'DXSPIDER_ROOT'} if $ENV{'DXSPIDER_ROOT'};
	
	unshift @INC, "$root/perl";	# this IS the right way round!
	unshift @INC, "$root/local";
}

use DXVars;
use DXUser;

$userfn = $ARGV[0] if @ARGV;

DXUser->init($userfn);

@all = DXUser::get_all_calls();
$t = scalar localtime;
print "#!/usr/bin/perl
#
# The exported userfile for a DXSpider System
# 
# Input file: $userfn
#       Time: $t
#

package DXUser;

%u = (
";

for $a (@all) {
	my $ref = DXUser->get($a);
	if (ref $ref) {
		my $s = $ref->encode();
	
		print "'$a' => q{ $s },\n";
	} else {
		print "# $a has gorn missing\n";
	}
	$count++;
}
print ");\n
#
# there were $count records
#\n";

