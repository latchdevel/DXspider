#
# disconnect a local user
#
my ($self, $line) = @_;
my @calls = split /\s+/, $line;
my $call;
my @out;

if ($self->priv < 9) {
  return (1, "not allowed");
}

foreach $call (@calls) {
  $call = uc $call;
  next if $call eq $main::mycall;
  my $dxchan = DXChannel->get($call);
  if ($dxchan) {
    if ($dxchan->is_ak1a) {
      $dxchan->send_now("D", DXProt::pc39($main::mycall, 'Disconnected'));
    } else {
      $dxchan->disconnect;
	} 
	push @out, "disconnected $call";
  } else {
    push @out, "$call not connected locally";
  }
}

return (1, @out);
