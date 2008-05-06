#!/usr/bin/perl
#
# Export the user file in a form that can be directly imported
# back with a do statement
#

require 5.004;

# search local then perl directories
BEGIN {
	umask 002;
	
	# root of directory tree for this system
	$root = "/spider"; 
	$root = $ENV{'DXSPIDER_ROOT'} if $ENV{'DXSPIDER_ROOT'};
	
	unshift @INC, "$root/perl";	# this IS the right way round!
	unshift @INC, "$root/local";
}

use DXVars;
use DB_File;
use Fcntl;
use Carp;

$userfn = $ARGV[0] if @ARGV;
unless ($userfn) {
	croak "need a filename";
}

DXUser->init($userfn);
unlink "$userfn.asc";
open OUT, ">$userfn.asc" or die;

%newu = ();
$t = scalar localtime;
print OUT "#!/usr/bin/perl
#
# The exported userfile for a DXSpider System
# 
# Input file: $userfn
#       Time: $t
#

package DXUser;

%u = (
";

@all = DXUser::get_all_calls();

for $a (@all) {
	my $ref = DXUser::get($a);
	my $s = $ref->encode() if $ref;
	print OUT "'$a' => q{$s},\n" if $a;
	$count++;
}

DXUser->finish();

print OUT ");
#
# there were $count records
#\n";

	close(OUT);

exit(0);


package DXUser;


use MLDBM qw(DB_File);
use Fcntl;
use Carp;

#
# initialise the system
#
sub init
{
	my ($pkg, $fn, $mode) = @_;
  
	confess "need a filename in User" if !$fn;
	if ($mode) {
		$dbm = tie (%u, MLDBM, $fn, O_CREAT|O_RDWR, 0666) or confess "can't open user file: $fn ($!)";
	} else {
		$dbm = tie (%u, MLDBM, $fn, O_RDONLY) or confess "can't open user file: $fn ($!)";
	}
	
	$filename = $fn;
}

#
# close the system
#

sub finish
{
	untie %u;
}

#
# get - get an existing user - this seems to return a different reference everytime it is
#       called - see below
#

sub get
{
	my $pkg = shift;
	my $call = uc shift;
	#  $call =~ s/-\d+$//o;       # strip ssid
	return $u{$call};
}

#
# get all callsigns in the database 
#

sub get_all_calls
{
	return (sort keys %u);
}


# 
# create a string from a user reference
#
sub encode
{
	my $self = shift;
	my $out;
	my $f;

	$out = "bless( { ";
	for $f (sort keys %$self) {
		my $val = $$self{$f};
	    if (ref $val) {          # it's an array (we think)
			$out .= "'$f'=>[ ";
			foreach (@$val) {
				my $s = $_;
				$out .= "'$s',";
			}
			$out .= " ],";
	    } else {
			$val =~ s/'/\\'/og;
			$val =~ s/\@/\\@/og;
			$out .= "'$f'=>'$val',";
		}
	}
	$out .= " }, 'DXUser')";
	return $out;
}

