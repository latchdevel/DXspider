#
# load the QSL file after changing it
#
my $self = shift;
return (1, $self->msg('e5')) if $self->priv < 9;
QSL::finish();
my $r = QSL::init(1);
my @out;
push @out, $self->msg($r ? 'ok':'e2', "$!");
return (1, @out);
