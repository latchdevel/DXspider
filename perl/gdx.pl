#
# grep for expressions in various fields of the dx file
#

use FileHandle;
use DXUtil;
use DXDebug;
use spot;

# initialise spots file
$count = spot->init();

dbgadd('spot');

$field = $ARGV[0];
$expr = $ARGV[1];
$time = time;

print "$count database records read in\n";

STDOUT->autoflush(1);

#loada();
for (;;) {
  print "field: ";
  $field = <STDIN>;
  last if $field =~ /^q/i;
  print "expr: ";
  $expr = <STDIN>;

  chomp $field;
  chomp $expr;

  print "doing field $field with /$expr/\n";

#a();
  b();
}

sub b
{
  my @spots;
  my @dx;
  my $ref;
  my $count;
  
  @spots = spot->search($field, $expr);
  
  foreach $ref (@spots) {
    @dx = @$ref;
	my $t = ztime($dx[2]);
	my $d = cldate($dx[2]);
	print "$dx[0] $dx[1] $d $t $dx[4] <$dx[3]>\n";
	++$count;
  }
  print "$count records found\n";
}

sub loada
{
  while (<IN>) {
    chomp;
	my @dx =  split /\^/;
	next if $time - $dx[2] > (84600 * 60);  
	unshift @spots, [ @dx ];
	++$count;
  }
}

sub a
{
  foreach $ref (@spots) {
    if ($$ref[$field] =~ /$expr/i) {
	  my @dx = @$ref;
	  my $t = ztime($dx[2]);
	  my $d = cldate($dx[2]);
      print "$dx[0] $dx[1] $d $t $dx[4] <$dx[3]>\n";
	}
  }
}

