#
# show the state of the DXUser statistics
#
#  Copyright (c) 2020 Dirk Koopman G1TLH
#
my $self = shift;

if ($self->priv < 9) {
	return (1, $self->msg('e5'));
}

my @out;

push @out, "      New Users: $DXUser::newusers";
push @out, " Modified Users: $DXUser::modusers";
push @out, "    Total Users: $DXUser::totusers";
push @out, "  Deleted Users: $DXUser::delusers";
push @out, "   Cached Users: $DXUser::cachedusers";

return (1, @out);
