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

my $call = $via ? $via : $to;
my $ref = DXCluster->get($call);
return (1, "$call not visible on the cluster") if !$ref;

my $dxchan = DXCommandmode->get($to);         # is it for us?
if ($dxchan && $dxchan->is_user) {
  $dxchan->send("$to de $from $line");
  Log('talk', $to, $from, $main::mycall, $line);
} else {
  $line =~ s/\^//og;            # remove any ^ characters
  my $prot = DXProt::pc10($from, $to, $via, $line);
  DXProt::route($via?$via:$to, $prot);
  Log('talk', $to, $from, $via?$via:$main::mycall, $line);
}

return (1, ());

