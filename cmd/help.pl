# 
# the help subsystem
#
# It is a very simple system in that you type in 'help <cmd>' and it
# looks for a file called <cmd>.hlp in either the local_cmd directory
# or the cmd directory (in that order). 
#
# if you just type in 'help' by itself you get what is in 'help.hlp'.
#
# Copyright (c) 1998 - Dirk Koopman G1TLH
#
# $Id$
#

my ($self, $line) = @_;
my @out;
my ($path, $fcmd) = ($main::cmd, "help");;
my @out;
my @inpaths = ($main::localcmd, $main::cmd);
my @helpfiles;

# this is naff but it will work for now
$line = "help" if !$line;
$fcmd = lc $line;

# each help file starts with a line that looks like:-
#
# === 0^EN^HELP^Description
# text
# text
# text 
#
# The fields are:- privilege level, Language, full command name, short description
#

if (!open(H, "$path/$fcmd.hlp")) {
  return (1, "no help on $line available");
}
my $in;
my $include = 0;
my @in = <H>;
close(H);

foreach $in (@in) {
  next if $in =~ /^\s*\#/;
  chomp $in;
  if ($in =~ /^===/) {
    $include = 0;
    $in =~ s/=== //;
	my ($priv, $lang, $cmd, $desc) = split /\^/, $in;
	next if $priv > $self->priv;             # ignore subcommands that are of no concern
	next if $self->lang && $self->lang ne $lang;
	push @out, "$cmd - $desc";
	$include = 1;
	next;
  }
  push @out, $in if $include;
}

push @out, "No help available for $line" if @out == 0;

return (1, @out);

