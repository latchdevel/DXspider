#
# the shutdown command
# 
# $Id$
#
my $self = shift;
my $call = $self->call;
my $ref;
return (1, $self->msg('e5')) unless $self->priv >= 5;
foreach $ref (DXChannel::get_all()) {
	$ref->send_now("D", DXProt::pc39($main::mycall, "Shutdown by $call")) if $ref->is_node  && $ref != $DXProt::me; 
	$ref->send_now("D", $self->msg('shutting')) if $ref->is_user;
}
    
# give some time for the buffers to empty and then shutdown (see cluster.pl)
$main::decease = 250;
	

return (1, $self->msg('shutting'));
