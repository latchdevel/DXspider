#
# The talk command
#
# Copyright (c) 1998 Dirk Koopman G1TLH
#
# $Id$
#

my ($self, $inline) = @_;
my $to;
my $via;
my $line;
my $from = $self->call;
my @out;
return (1, $self->msg('e5')) if $self->remotecmd;

# analyse the line there are four situations...
# 1) talk call
# 2) talk call <text>
# 3) talk call>node 
# 4) talk call>node text
#

($to, $via, $line) = $inline =~ /^\s*([A-Za-z0-9\-]+)\s*>([A-Za-z0-9\-]+)(.*)$/;
if ($via) {
	$line =~ s/\s+// if $line;
} else {
	($to, $line) = split /\s+/, $inline, 2;  
}

$to = uc $to if $to;
$via = uc $via if $via;
my $call = $via ? $via : $to;
my $clref = DXCluster->get_exact($call);     # try an exact call
my $dxchan = $clref->dxchan if $clref;
return (1, $self->msg('e7', $call)) unless $dxchan;

# if there is a line send it, otherwise add this call to the talk list
# and set talk mode for command mode
if ($line) {
	$dxchan->talk($self->call, $to, $via, $line) if $dxchan;
} else {
	my $s = $to;
	$s .= ">$via" if $via;
	my $ref = $self->talklist;
	if ($ref) {
		unless (grep { $_ eq $s } @$ref) {
			$dxchan->talk($self->call, $to, $via, $self->msg('talkstart'));
			$self->state('talk');
			push @$ref, $s;
		}
	} else { 
		$self->talklist([ $s ]);
		$dxchan->talk($self->call, $to, $via, $self->msg('talkstart'));
		push @out, $self->msg('talkinst');
		$self->state('talk');
	}
	push @out, $self->talk_prompt;
}

return (1, @out);

