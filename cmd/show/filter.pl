#
# show filter commands
#
# Copyright (c) 2000 Dirk Koopman G1TLH
#
# $Id$
#
my ($self, $line) = @_;
my @f = split /\s+/, $line;
my @out;
my $dxchan = $self;
my $sort = '';

my $f = lc shift @f if @f;
if ($self->priv >= 8) {
	my $d = DXChannel->get(uc $f);
	$dxchan = $d if $d;
	$f = lc shift @f if @f;
}

$sort = $f if $f;
$sort .= 'filter';

my $key;
foreach $key (sort keys %$self) {
	if ($key =~ /$sort$/) {
		push @out, $self->{$key}->print if $self->{$key};
	}
}
push @out, $self->msg('filter3', $dxchan->call) unless @out;
return (1, @out);
