#
# Query the DB0SDX QSL server for a callsign
#
# Copyright (c) 2003 Dirk Koopman G1TLH
# Modified Dec 9, 2004 for new website and xml schema by David Spoelstra N9KT
# and tidied up by me (Dirk)
#
#
#

sub on_disc
{
	my $conn = shift;
	my $dxchan = shift;
	my @out;
	
	dbg("keps in: $conn->{kepsin}") if isdbg('keps');

	$dxchan->send("get/keps: new keps loaded");
}

sub process
{
	my $conn = shift;
	my $msg = shift;

	$conn->{kepsin} .= "$msg\n";
	
	dbg("keps in: $conn->{kepsin}") if isdbg('keps');
}

sub handle
{
	my ($self, $line) = @_;
	my $call = $self->call;
	my @out;

	$line = uc $line;
	return (1, $self->msg('e24')) unless $Internet::allow;
	my $target = $Internet::keps_url || 'www.amsat.org';
	my $path = $Internet::keps_path || '/amsat/ftp/keps/current/nasa.all';
	my $port = 80;

	dbg("keps: contacting $target:$port") if isdbg('keps');

	Log('call', "$call: show/keps $line");
	my $conn = AsyncMsg->post($self, $target, $port, $path, 
							  filter => \&process,
							  on_disc => \&on_disc);
	
	if ($conn) {
		push @out, $self->msg('m21', "show/keps");
	} else {
		push @out, $self->msg('e18', 'get/keps error');
	}

	return (1, @out);
}
