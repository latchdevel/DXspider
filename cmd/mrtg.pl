#
# This is a local command to generate the various statistics that
# can then be displayed on an MRTG plot
#
# Your mrtg binary must live in one of the standard places
#
# The arguments (keywords) to the mrtg command are these
#
# a) content          (you always get the node users and nodes)
#    totalspots       - all spots
#    hfvhf            - all spots split into HF and VHF
#    wwv              - two graphs of WWV, one SFI and R other A and K
#    wcy              - WCY A and K 
#    all              - all of the above 
#    
# b) actions          
#    test             - do everything except check for and run mrtg
#    nomrtg           - ditto (better name)
#    dataonly         - only generate the data files for mrtg
#    cfgonly          - only generate the mrtg.cfg file (like cfgmaker)
#    runmrtg          - run mrtg, this is probably used with dataonly
#                     - together with a home rolled mrtg.cfg 
#
# Copyright (c) 2002 Dirk Koopman G1TLH
#
# $Id$
#

my ($self, $line) = @_;

# create the arg list
my %want;
for (split /\s+/, $line) { $want{lc $_} = 1};
$want{nomrtg} = 1 if $want{cfgonly} || $want{test};
 			 
return (1, "MRTG not installed") unless $want{nomrtg} || -e '/usr/bin/mrtg' || -e '/usr/local/bin/mrtg';

my $mc = new Mrtg or return (1, "cannot initialise Mrtg $!");
			 
# do the users and nodes
my $users = DXChannel::get_all_users();
my $nodes = DXChannel::get_all_nodes();

$mc->cfgprint('users', [qw(unknaszero gauge)], 500, 
		 "Users and Nodes on $main::mycall",
		 'Users / Nodes', 'Users', 'Nodes') unless $want{dataonly};
$mc->data('users', $users, $nodes, 'Users / Nodes') unless $want{cfgonly};

# do the  total users and nodes
if ($want{totalusers} || $want{all}) {
	$nodes = Route::Node::count();
	$users = Route::User::count();
	$mc->cfgprint('totalusers', [qw(unknaszero gauge)], 10000, 
			'Total Users and Nodes in the Visible Cluster Network',
			 'Users / Nodes', 'Users', 'Nodes') unless $want{dataonly};
	$mc->data('totalusers', $users, $nodes, 'Total Users and Nodes in the Visible Cluster Network') unless $want{cfgonly};
}

# do the total spots
if ($want{totalspots} || $want{all}) {
	$mc->cfgprint('totalspots',  [qw(unknaszero gauge noi)], 1000, 'Total Spots',
			 'Spots', 'Spots', 'Spots') unless $want{dataonly};
	$mc->data('totalspots', $Spot::totalspots, $Spot::totalspots, 'Total Spots') unless $want{cfgonly};
	$Spot::totalspots = 0;
}

# do the HF and VHF spots
if ($want{hfvhf} || $want{all}) {
	$mc->cfgprint('hfspots', [qw(unknaszero gauge)], 1000, 'HF and VHF+ Spots',
			 'Spots', 'HF', 'VHF') unless $want{dataonly};
	$mc->data('hfspots', $Spot::hfspots, $Spot::vhfspots, 'HF and VHF+ Spots') unless $want{cfgonly};
	$Spot::hfspots = $Spot::vhfspots = 0;
}

# wwv stuff
if ($want{wwv} || $want{all}) {
	$mc->cfgprint('wwvsfi', [qw(gauge)], 1000, 'WWV SFI and R',
			 'SFI / R', 'SFI', 'R') unless $want{dataonly};
	$mc->data('wwvsfi', ($Geomag::r || $WCY::r), ($Geomag::sfi || $WCY::sfi), 'WWV SFI and R') unless $want{cfgonly};
	$mc->cfgprint('wwvka', [qw(gauge)], 1000, 'WWV A and K',
			 'A / K', 'A', 'K') unless $want{dataonly};
	$mc->data('wwvka', $Geomag::a, $Geomag::k, 'WWV A and K') unless $want{cfgonly};
}

# WCY stuff
if ($want{wcy} || $want{all}) {
	$mc->cfgprint('wcyka', [qw(gauge)], 1000, 'WCY A and K',
			 'A / K', 'A', 'K') unless $want{dataonly};
	$mc->data('wcyka', $WCY::a, $WCY::k, 'WCY A and K') unless $want{cfgonly};
}

# 
# do the mrtg thing
#
my @out = $mc->run unless $want{nomrtg};
return (1, @out);
