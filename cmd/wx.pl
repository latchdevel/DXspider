#
# do an wx message, this is identical to the announce except that it does WX
# instead
#
# handles wx
#         wx full
#         wx sysop
#
# at the moment these keywords are fixed, but I dare say a file containing valid ones
# will appear
#
# Copyright (c) 1998 Dirk Koopman G1TLH
#
# $Id$
#

my ($self, $line) = @_;
my @f = split /\s+/, $line;
my $sort = uc $f[0];
my @locals = DXCommandmode->get_all();
my $to;
my $from = $self->call;
my $t = ztime(time);
my $tonode;
my $sysopflag;

if ($sort eq "FULL") {
  $line =~ s/^$f[0]\s+//;    # remove it
  $to = "ALL";
} elsif ($sort eq "SYSOP") {
  $line =~ s/^$f[0]\s+//;     # remove it
  @locals = map { $_->priv >= 5 ? $_ : () } @locals;
  $to = "SYSOP";
  $sysopflag = '*';
} else {
  $to = "LOCAL";
}

DXProt::broadcast_list("WX de $from <$t>: $line", @locals);
if ($to ne "LOCAL") {
  $line =~ s/\^//og;    # remove ^ characters!
  my $pc = DXProt::pc12($from, $line, $tonode, $sysopflag, 1);
  DXProt::broadcast_ak1a($pc);
}

return (1, ());
