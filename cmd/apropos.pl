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

my $in;
$line = 'help' unless $line;
$line =~ s/\W//g;   # remove dubious characters

my ($priv, $cmd, $desc);
my %cmd;

my $defh = new IO::File;
unless ($defh->open("$main::localcmd/Commands_en.hlp")) {
	unless($defh->open("$main::cmd/Commands_en.hlp")) {
		return (1, $self->msg('helpe1'));
	}
}

my $h;
if ($lang ne 'en') {
	$h = new IO::File;
	unless ($h->open("$main::localcmd/Commands_$lang.hlp")) {
		unless($h->open("$main::cmd/Commands_$lang.hlp")) {
			undef $h;
		}
	}
}

# do english help
my $include;
foreach $in (<$defh>) {
	next if $in =~ /^\#/;
	chomp $in;
	$in =~ s/\r$//;
	if ($in =~ /^===/) {
		$cmd{$cmd} = "$cmd $desc" if $include;
		$include = 0;
		$in =~ s/=== //;
		($priv, $cmd, $desc) = split /\^/, $in;
		next if $priv > $self->priv;             # ignore subcommands that are of no concern
		next unless $cmd =~ /$line/i || $desc =~ /$line/i;
		next if $cmd =~ /-$/o;
		$include = 1;
		next;
	}
	$include = 1 if $cmd =~ /$line/i;
}
$cmd{$cmd} = "$cmd $desc" if $include;
$defh->close;

# override with any not english help
if ($h) {
	my $include;
	foreach $in (<$h>) {
		next if $in =~ /^\#/;
		chomp $in;
		$in =~ s/\r$//;
		if ($in =~ /^===/) {
			$cmd{$cmd} = "$cmd $desc" if $include;
			$include = 0;
			$in =~ s/=== //;
			($priv, $cmd, $desc) = split /\^/, $in;
			next if $priv > $self->priv;             # ignore subcommands that are of no concern
			next unless $cmd =~ /$line/i || $desc =~ /$line/i;
			next if $cmd =~ /-$/o;
			$include = 1;
			next;
		}
		$include = 1 if $cmd =~ /$line/i;
	}
	$cmd{$cmd} = "$cmd $desc" if $include;
	$h->close;
}

push @out, map {$cmd{$_}} sort keys %cmd;

push @out, $self->msg('helpe2', $line) if @out == 0;

return (1, @out);
