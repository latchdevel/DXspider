#
# show either the current user or a nominated set
#
# $Id$
#

my ($self, $line) = @_;
my @list = DXChannel->get_all();
my $chan;
my @out;
foreach $chan (@list) {
  push @out, "Callsign: $chan->{call}";
}

return (1, @out);
