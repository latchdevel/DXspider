#!/usr/bin/perl
#
# grep for expressions in various fields of the dx file
#

use FileHandle;
use DXUtil;
use DXDebug;
use Spot;

# initialise spots file
STDOUT->autoflush(1);

#print "reading in spot data ..";
#$t = time;
#$count = Spot->init();
#$t = time - $t;
#print "done ($t secs)\n";

dbgadd('spot');

$field = $ARGV[0];
$expr = $ARGV[1];
$time = time;

#loada();
for (;;) {
  print "expr: ";
  $expr = <STDIN>;
  last if $expr =~ /^q/i;

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
  my $i;
  
  my $t = time;
  @spots = Spot::search($expr);
  if ($spots[0] eq "error") {
    print $spots[1];
	return;
  }
  foreach $ref (@spots) {
    @dx = @$ref;
	my $t = ztime($dx[2]);
	my $d = cldate($dx[2]);
	print "$dx[0] $dx[1] $d $t $dx[4] <$dx[3]>\n";
	++$count;
  }
  $t = time - $t;
  print "$count records found, $t secs\n";
}

sub search
{
  my ($expr, $from, $to) = @_;
  my $eval;
  my @out;
  my @spots;
  my $ref;
  my $i;


  $expr =~ s/\$f(\d)/zzzref->[$1]/g;               # swap the letter n for the correct field name
  $expr =~ s/[\@\$\%\{\}]//g;                           # remove any other funny characters
  $expr =~ s/\&\w+\(//g;                           # remove subroutine calls
  $expr =~ s/eval//g;                              # remove eval words
  $expr =~ s/zzzref/\$ref/g;                       # put back the $ref
  
  print "expr = $expr\n";
  
  # build up eval to execute
  $eval = qq(my \$c;
    for (\$c = \$#spots; \$c >= 0; \$c--) {
	  \$ref = \$spots[\$c];
	  if ($expr) {
        push(\@out, \$ref);
	  }
  });

  my @today = Julian::unixtoj(time);
  for ($i = 0; $i < 60; ++$i) {
    my @now = Julian::sub(@today, $i);
	my @spots;
	my $fp = Spot->open(@now);
	if ($fp) {
	  my $fh = $fp->{fh};
	  my $in;
	  foreach $in (<$fh>) {
	    chomp $in;
        push @spots, [ split('\^', $in) ];
	  }
	  my $ref;
	  eval $eval;
	  return ("error", $@) if $@;
	}
  }
                               # execute it
  return @out;
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

