#
# This is a local command to generate the various statistics that
# can then be displayed on an MRTG plot
#
# Your mrtg binary must live in one of the standard places
#
# you will need perl 5.6 (probably) to be able to run this command
#

my ($self, $line) = @_;

# create the arg list
my %want;
for (split /\s+/, $line) { $want{lc $_} = 1};
			 
return (1, "MRTG not installed") unless $want{test} || -e '/usr/bin/mrtg' || -e '/usr/local/bin/mrtg';

my $mc = new Mrtg or return (1, "cannot initialise Mrtg $!");
			 
# do the users and nodes
my $users = DXChannel::get_all_users();
my $nodes = DXChannel::get_all_nodes();

$mc->cfgprint('users', $users, $nodes, [qw(gauge)], 500, 
		 "Users and Nodes on $main::mycall",
		 'Users / Nodes', 'Users', 'Nodes');

# do the  total users and nodes
if ($want{totalusers} || $want{all}) {
	$nodes = Route::Node::count();
	$users = Route::User::count();
	$mc->cfgprint('totalusers', $users, $nodes,  [qw(gauge)], 10000, 
			'Total Users and Nodes in the Visible Cluster Network',
			 'Users / Nodes', 'Users', 'Nodes');
}

# do the total spots
if ($want{totalspots} || $want{all}) {
	$mc->cfgprint('totalspots', $Spot::totalspots, $Spot::totalspots, [qw(unknaszero gauge noi)], 1000, 'Total Spots',
			 'Spots', 'Spots', 'Spots');
	$Spot::totalspots = 0;
}

# do the HF and VHF spots
if ($want{hfvhf} || $want{all}) {
	$mc->cfgprint('hfspots', $Spot::hfspots, $Spot::vhfspots, [qw(unknaszero gauge)], 1000, 'HF and VHF+ Spots',
			 'Spots', 'HF', 'VHF');
	$Spot::hfspots = $Spot::vhfspots = 0;
}

# wwv stuff
if ($want{wwv} || $want{all}) {
	$mc->cfgprint('wwvsfi', $Geomag::r || $WCY::r, $Geomag::sfi || $WCY::sfi, [qw(gauge)], 1000, 'WWV SFI and R',
			 'SFI / R', 'SFI', 'R');
	$mc->cfgprint('wwvka', $Geomag::a, $Geomag::k, [qw(gauge)], 1000, 'WWV A and K',
			 'A / K', 'A', 'K');
}

# WCY stuff
if ($want{wcy} || $want{all}) {
	$mc->cfgprint('wcyka', $WCY::a, $WCY::k, [qw(gauge)], 1000, 'WCY A and K',
			 'A / K', 'A', 'K');
}

# 
# do the mrtg thing
#
my @out = $mc->run unless $want{test};
return (1, @out);
