#
# do a chat message
#
# this is my version of conferencing....
#
# Copyright (c) 2003 Dirk Koopman G1TLH
#
# $Id$
#

my ($self, $line) = @_;
my @f = split /\s+/, $line, 2;
return (1, $self->msg('e5')) if $self->remotecmd;
return (1, $self->msg('e34')) unless @f == 2;
return (1, $self->msg('e28')) unless $self->registered;

my $target = uc $f[0];

return (1, $self->msg('e35', $target)) unless grep uc $_ eq $target, @{$self->user->group};

my $from = $self->call;
my $text = unpad $f[1];
my $t = ztime(time);
my $toflag = '*';

# change ^ into : for transmission
$line =~ s/\^/:/og;

my @bad;
if (@bad = BadWords::check($line)) {
	$self->badcount(($self->badcount||0) + @bad);
	Log('DXCommand', "$self->{call} swore: $line");
	Log('chat', $target, $from, "[to $from only] $line");
	return (1, "$target de $from <$t>: $line");
}

#PC12^IZ4DYU^GROUP^PSE QSL INFO TO A71AW TNX IN ADV 73's^ ^IK5PWJ-6^0^H21^~
my $msgid = DXProt::nextchatmsgid();
$text = "#$msgid $text";

DXProt::send_chat($self, DXProt::pc12($from, $text, '*', $target), $from, $target, $text, ' ', $main::mycall, '0');

return (1, ());
