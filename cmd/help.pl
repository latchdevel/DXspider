# 
# the help subsystem
#
# It is a very simple system in that you type in 'help <cmd>' and it
# looks for a file called command.hlp in either the local_cmd directory
# or the cmd directory (in that order). 
#
# Copyright (c) 1998 - Dirk Koopman G1TLH
#
# $Id$
#

my ($self, $line) = @_;
my @out;

# this is naff but it will work for now
$line = "help" if !$line;
my $lang = $self->lang;
$lang = 'en' if !$lang;

# each help file contains lines that looks like:-
#
# === 0^EN^*^Description
# text
# text
#
# === 0^EN^help^Description
# text
# text
# text 
#
# The fields are:- privilege level, Language, full command name, short description
#

my $h = new IO::File;

if (!open($h, "$main::localcmd/Commands_$lang.hlp")) {
	if (!open($h, "$main::cmd/Commands_$lang.hlp")) {
		return (1, $self->msg('helpe1'));
	}
}
my $in;

$line =~ s/![\w\/]//og;
$line =~ s/\//\.\*\//og;
$line =~ s/^\s+//og;
$line =~ s/\s+$//og;

# sort out aliases
my $alias = CmdAlias::get_hlp($line);
$line = $alias if $alias;

my $include;
foreach $in (<$h>) {
	next if $in =~ /^\#/;
	chomp $in;
	if ($in =~ /^===/) {
		$include = 0;
		$in =~ s/=== //;
		my ($priv, $cmd, $desc) = split /\^/, $in;
		next if $priv > $self->priv;             # ignore subcommands that are of no concern
		next unless $cmd =~ /$line/i;
		push @out, "$cmd $desc" unless $cmd =~ /-$/o;
		$include = 1;
		next;
	}
	push @out, "   $in" if $include;
}

close($h);

push @out, $self->msg('helpe2', $line) if @out == 0;

return (1, @out);

