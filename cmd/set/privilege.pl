#
# set the privilege of the user
#
# call as set/priv n <call> ...
#
# Copyright (c) 1998 Dirk Koopman G1TLH
#
# $Id$
#
my ($self, $line) = @_;
my @args = split /\s+/, $line;
my $call;
my $priv = shift @args;
my @out;
my $user;

$DB::single = 1;

return (0) if $self->priv < 9;

if ($priv < 0 || $priv > 9) {
  return (0, $self->msg('e5')); 
}

foreach $call (@args) {
  $call = uc $call;
  my $user = DXUser->get_current($call);
  if ($user) {
    $user->priv($priv);
	$user->put();
    push @out, $self->msg('priv', $call);
  } else {
    push @out, $self->msg('e3', "Set Privilege", $call);
  }
}
return (1, @out);
