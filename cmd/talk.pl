#
# The talk command
#
# $Id$
#

my ($self, $line) = @_;
my @argv = split /\s+/, $line;		      # generate an argv
my $to = uc $argv[0];
my $via;
my $from = $self->call();

if ($argv[1] eq '>') {
  $via = uc $argv[2];
#  print "argv[0] $argv[0] argv[2] $argv[2]\n";
  $line =~ s/^$argv[0]\s+>\s+$argv[2]\s*//o;
} else {
#  print "argv[0] $argv[0]\n";
  $line =~ s/^$argv[0]\s*//o;
}

#print "to=$to via=$via line=$line\n";
my $dxchan = DXCommandmode->get($to);         # is it for us?
if ($dxchan && $dxchan->is_user) {
  $dxchan->send("$to de $from $line");
} else {
  my $prot = DXProt::pc10($self, $to, $via, $line);
#  print "prot=$prot\n";

  DXProt::route($via?$via:$to, $prot);
}

return (1, ());

