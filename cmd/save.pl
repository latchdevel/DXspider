# 
# save the output of ANY command to a file
#
# Copyright (c) 2002 Dirk Koopman G1TLH
#
# $Id$
#

my ($self, $line) = @_;
return (1, $self->msg('e5')) if $self->priv < 9 || $self->remotecmd;

my ($date_req, $time_req);
my $app_req = '>';
if ($line =~ /-d/) {			# add a date to the end of the filename
	$line =~ s/\s*-d\s*//;
	$date_req = 1;
}
if ($line =~ /-t/) {			# add a time to the end of the filename
	$line =~ s/\s*-t\s*//;
	$time_req = 1;
}
if ($line =~ /-a/) {			# append to the file
	$line =~ s/\s*-a\s*//;
	$app_req = '>>';
}

my ($fn, $rest) = split /\s+/, $line, 2;
$fn .= '_' . cldate if $date_req;
$fn .= '_' . ztime if $time_req;
$fn =~ s/\s+//g;

my @cmd;
if ($rest =~ /^\s*\"/) {
	@cmd = split /\s*\"[\s,]?\"?/, $rest;
} else {
	push @cmd, $rest;
}
open OF, "$app_req$fn" or return (1, $self->msg('e30', $fn));
for (@cmd) {
	print OF map {"$_\n"} $self->run_cmd($_);
}
close OF;
return (1, $self->msg('ok'));

