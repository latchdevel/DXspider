#
# accept/reject filter commands
#
# Copyright (c) 2000 Dirk Koopman G1TLH
#
# $Id$
#

my ($self, $line) = @_;
my $sort = 'reject';

return (0, $self->msg('filter5')) unless $line;

my ($r, $filter, $fno, $user, $s) = $Spot::filterdef->parse($self, $line);
return (0, $filter) if $r;

my $fn = "filter$fno";

$filter->{$fn} = {} unless exists $filter->{$fn};
$filter->{$fn}->{$sort} = {} unless exists $filter->{$fn}->{$sort};

$filter->{$fn}->{$sort}->{user} = $user;
my $ref = eval $s;
return (0, $s, $@) if $@;

$filter->{$fn}->{$sort}->{asc} = $s;
$r = $filter->write;
return (0, $r) if $r;

$filter->{$fn}->{$sort}->{code} = $ref;
$filter->install;

return (0, $self->msg('filter1', $fno, $filter->{name})); 
