#
# set a user's password
#
# Copyright (c) 1998 Iain Phillips G0RDI
# 21-Dec-1998
#
# Syntax:	set/pass <callsign> <password> 
#

my ($self, $line) = @_;
my @args = split /\s+/, $line;
my $call = shift @args;
my @out;
my $user;
my $ref;

return (1, $self->msg('e5')) if $self->priv < 9;

if ($ref = DXUser->get_current($call)) {
	$line =~ s/^\s*$call\s+//;
	$line =~ s/\s+//og;                    # remove any blanks
	$line =~ s/[{}]//g;   # no braces allowed
	$ref->passwd($line);
	$ref->put();
	push @out, $self->msg("password", $call);
} else {
	push @out, $self->msg('e3', 'User record for', $call);
}

return (1, @out);
