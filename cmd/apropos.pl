# 
# the help subsystem
#
# apropos - this does a grep on the command file and returns the commands
# that contain the string searched for
#
# Copyright (c) 1998 - Dirk Koopman G1TLH
#
# $Id$
#

my ($self, $line) = @_;
my @out;

my $lang = $self->lang;
$lang = 'en' if !$lang;

my $h = new FileHandle;

if (!open($h, "$main::localcmd/Commands_$lang.hlp")) {
	if (!open($h, "$main::cmd/Commands_$lang.hlp")) {
		return (1, $self->msg('helpe1'));
	}
}
my $in;

$line =~ s/\W//og;   # remove dubious characters

my $include;
my ($priv, $cmd, $desc);

foreach $in (<$h>) {
	next if $in =~ /^\#/;
	chomp $in;
	if ($in =~ /^===/) {
		push @out, "$cmd $desc" if $include;
		$include = 0;
		$in =~ s/=== //;
		($priv, $cmd, $desc) = split /\^/, $in;
		next if $priv > $self->priv;             # ignore subcommands that are of no concern
		next unless $cmd =~ /$line/i || $desc =~ /$line/i;
		next if $cmd =~ /-$/o;
		$include = 1;
		next;
	}
	$include =~ 1 if $cmd =~ /$line/i;
}
push @out, "$cmd $desc" if $include;

close($h);

push @out, $self->msg('helpe2', $line) if @out == 0;

return (1, @out);
