#
# disconnect a local user
#
my ($self, $line) = @_;
my @calls = split /\s+/, $line;
my $call;
my @out;

if ($self->priv < 8) {
  return (1, $self->msg('e5'));
}

foreach $call (@calls) {
  $call = uc $call;
  next if $call eq $main::mycall;
  my $dxchan = DXChannel->get($call);
  if ($dxchan) {
    if ($dxchan->is_ak1a) {
      $dxchan->send_now("D", DXProt::pc39($main::mycall, $self->msg('disc1', $self->call)));
    } else {
	  $dxchan->send_now('D', $self->msg('disc1', $self->call));
	} 
    $dxchan->disconnect;
	push @out, $self->msg('disc2', $call);
  } else {
    push @out, $self->msg('e10', $call);
  }
}

return (1, @out);
