#
# do a tradiotional "uptime" clone
#
my $self = shift;

return (1, sprintf("%s $main::mycall uptime: %s", ztime(), difft($main::starttime, ' ')));
