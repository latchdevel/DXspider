#
# The talk command
#
# Copyright (c) 1998 Dirk Koopman G1TLH
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
  $line =~ s/^$argv[0]\s+>\s+$argv[2]\s*//;
} else {
  $line =~ s/^$argv[0]\s*//;
}

my $dxchan = DXCommandmode->get($to);         # is it for us?
if ($dxchan && $dxchan->is_user) {
  $dxchan->send("$to de $from $line");
} else {
  $line =~ s/\^//og;            # remove any ^ characters
  my $prot = DXProt::pc10($self, $to, $via, $line);
  DXProt::route($via?$via:$to, $prot);
}

return (1, ());

