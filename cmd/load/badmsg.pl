# reload the badmsg file
my $self = shift;
my @out;
return (0, $self->msg('e5')) if $self->priv < 9;
do "$main::data/badmsg.pl" if -e "$main::data/badmsg.pl";
push @out, $@ if $@;
@out = ($self->msg('ok')) unless @out;
return (1, @out); 
