#
# the shutdown command
# 
# $Id$
#
my $self = shift;
my $call = $self->call;
my $ref;

if ($self->priv >= 5) {
	foreach $ref (DXChannel::get_all()) {
		$ref->send_now("D", DXProt::pc39($main::mycall, "Shutdown by $call")) 
			if $ref->is_ak1a  && $ref != $DXProt::me; 
		$ref->send_now("D", $self->msg('shutting')) if $ref->is_user;
	}
    
    # give some time for the buffers to empty and then shutdown (see cluster.pl)
	$main::decease = 250;
}
return (1);
