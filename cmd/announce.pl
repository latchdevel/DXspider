#
# do an announce message 
#
# handles announce
#         announce full
#         announce sysop
#
# at the moment these keywords are fixed, but I dare say a file containing valid ones
# will appear
#
# Copyright (c) 1998 Dirk Koopman G1TLH
#
# $Id$
#
# Modified 13Dec98 Iain Phillips G0RDI
#

my ($self, $line) = @_;
my @f = split /\s+/, $line;
return (1, $self->msg('e5')) if $self->remotecmd || $self->inscript;
return (1, $self->msg('e9')) if !@f;
return (1, $self->msg('e28')) unless $self->registered;

my $sort = uc $f[0];
my @locals = DXCommandmode->get_all();
my $to;
my $from = $self->call;
my $t = ztime(time);
my $tonode;
my $toflag = '*';
my $sysopflag;

if ($sort eq "FULL") {
  $line =~ s/^$f[0]\s+//;    # remove it
  $to = "ALL";
} elsif ($sort eq "SYSOP") {
  $line =~ s/^$f[0]\s+//;     # remove it
  @locals = map { $_->priv >= 5 ? $_ : () } @locals;
  $to = "SYSOP";
  $sysopflag = '*';
} elsif ($sort eq "LOCAL") {
  $line =~ s/^$f[0]\s+//;     # remove it
  $to = "LOCAL";
} else {
  $to = "LOCAL";
}

# change ^ into : for transmission
$line =~ s/\^/:/og;

my @bad;
if (@bad = BadWords::check($line)) {
	$self->badcount(($self->badcount||0) + @bad);
	Log('DXCommand', "$self->{call} swore: $line");
	Log('ann', $to, $from, "[to $from only] $line");
	$self->send("To $to de $from <$t>: $line");
	return (1, ());
}

return (1, $self->msg('dup')) if $self->priv < 5 && AnnTalk::dup($from, $toflag, $line);
Log('ann', $to, $from, $line);
DXChannel::broadcast_list("To $to de $from ($t): $line\a", 'ann', undef, @locals);
if ($to ne "LOCAL") {
  my $pc = DXProt::pc12($from, $line, $tonode, $sysopflag, 0);
  DXChannel::broadcast_nodes($pc);
}

return (1, ());
