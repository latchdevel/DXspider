#
# show the contents of the message directory
#
# Copyright (c) Dirk Koopman G1TLH
#
# $Id$
#

my ($self, $line) = @_;
my @f = split /\s+/, $line;
my @ref;
my $ref;
my @out;
my $f;
my $n = 10;

if (!@f) {
	my @all = (DXMsg::get_all());
	my ($i, $count);
	for ($i = $#all; $i > 0; $i--) {
		$ref = $all[$i];
		next if $self->priv < 5 && $ref->private && $ref->to ne $self->call && $ref->from ne $self->call;
		unshift @ref, $ref;
		last if ++$count >= $n;
	}
}

while (@f) {
	$f = uc shift @f;
	if ($f eq 'ALL') {
		foreach $ref (DXMsg::get_all()) { 
			next if $self->priv < 5 && $ref->private && $ref->to ne $self->call && $ref->from ne $self->call;
			push @ref, $ref;
		}
		last;
	} elsif ($f =~ /^O/o) {		# dir/own
		foreach $ref (DXMsg::get_all()) { 
			push @ref, $ref if $ref->private && ($ref->to eq $self->call || $ref->from eq $self->call);
		}
	} elsif ($f =~ /^N/o) {		# dir/new
		foreach $ref (DXMsg::get_all()) { 
			push @ref, $ref if $ref->private && !$ref->read && $ref->to eq $self->call;
		}
	} elsif ($f eq '>' || $f eq 'TO'){
		$f = uc shift @f;
		if ($f) {
			$f = shellregex($f);
			foreach $ref (DXMsg::get_all()) { 
				next if $self->priv < 5 && $ref->private && $ref->to ne $self->call && $ref->from ne $self->call;
				next unless $ref->to =~ m{$f};
				push @ref, $ref;
			}
		}
	} elsif ($f eq '<' || $f eq 'FROM'){
		$f = uc shift @f;
		if ($f) {
			$f = shellregex($f);
			foreach $ref (DXMsg::get_all()) { 
				next if $self->priv < 5 && $ref->private && $ref->to ne $self->call && $ref->from ne $self->call;
				next unless $ref->from =~ m{$f};
				push @ref, $ref;
			}
		}
	} elsif ($f =~ /^\d+$/ && $f > 0) {		# a number of items
		$n = $f;
	}
}

if (@ref) {
	my $i = @ref - $n;
	$i = 0 unless $i > 0;
	my $count;
	while ($i < @ref) {
		$ref = $ref[$i++];
		push @out, $ref->dir;
		last if ++$count >= $n;
	}
} else {
	push @out, $self->msg('e3', 'directory', $line); 
}
return (1, @out);
