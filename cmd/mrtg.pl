#
# This is a local command to generate the various statistics that
# can then be displayed on an MRTG plot
#
# Your mrtg binary must live in one of the standard places
#
my ($self, $line) = @_;

return (1) unless -e '/usr/bin/mrtg' || -e '/usr/local/bin/mrtg';

my $dir = "$main::root/mrtg";
my $html = "$main::root/html/mrtg";
my $cfg = "$dir/mrtg.cfg";

# do some checking
return (1, "$dir is missing") unless -d $dir;
return (1, "$html is missing") unless -d $html; 
return (1, "$cfg is missing") unless -e "$cfg";
open MC, ">$cfg" or return(1, "cannot open $cfg for mrtg writing");

# print out the header
print MC <<"EOF";
### Global Defaults

#  to get bits instead of bytes and graphs growing to the right
# Options[_]: growright, bits

Htmldir: $html
Imagedir: $html
Logdir: $dir
Options[_]: growright

##
##

EOF

# create the arg list
my %want;
for ( split /\s+/, $line) {
	$want{lc $_} = 1;
}; 

#dbg "$dir\n$html\n";

# do the users and nodes
my $users = DXChannel::get_all_users();
my $nodes = DXChannel::get_all_nodes();
my $uptime = main::uptime();
#dbg "$users $nodes $uptime\n";
if (open M, ">$dir/users") {
	print M "$users\n$nodes\n$uptime\nUsers and Nodes\n";
	close M;
}
print MC <<"EOF";
#
# local users and nodes
#
Target[users]: `cat /spider/mrtg/users`
MaxBytes1[users]: 500
MaxBytes2[users]: 200
Title[users]: Users and Nodes for $main::mycall
Options[users]: withzeroes, gauge, growright, nopercent, integer
YLegend[users]: Users \&amp; Nodes
YTicsFactor[users]: 1
ShortLegend[users]: \&nbsp;
Legend1[users]:Maximum No of Users
Legend2[users]:Maximum No of Nodes
LegendI[users]:Users
LegendO[users]:Nodes
PageTop[users]: <H1>Users and Nodes on GB7DJK</H1>
 <TABLE>
   <TR><TD>System:</TD>     <TD>$main::mycall</TD></TR>
   <TR><TD>Maintainer:</TD> <TD>$main::myemail</TD></TR>
   <TR><TD>Description:</TD><TD>Users \&amp; Nodes </TD></TR>
 </TABLE>
EOF

# do the  total users and nodes
if ($want{totalusers} || $want{all}) {
	$nodes = Route::Node::count();
	$users = Route::User::count();
	#dbg "$users $nodes $uptime\n";
	if (open M, ">$dir/totalusers") {
		print M "$users\n$nodes\n$uptime\nTotal Users and Nodes\n";
		close M;
	}
	print MC <<"EOF";
#
# total users and nodes
#
Target[totalusers]: `cat /spider/mrtg/totalusers`
MaxBytes1[totalusers]: 5000
MaxBytes2[totalusers]: 5000
Title[totalusers]: Total Users and Nodes for the Visible Cluster Network
Options[totalusers]: withzeroes,  gauge, growright, nopercent, integer
YLegend[totalusers]: Users \&amp; Nodes
YTicsFactor[totalusers]: 1
ShortLegend[totalusers]: \&nbsp;
Legend1[totalusers]:Maximum No of Users
Legend2[totalusers]:Maximum No of Nodes
LegendI[totalusers]:Users
LegendO[totalusers]:Nodes
PageTop[totalusers]: <H1>Total Users and Nodes in the Visible Network</H1>
 <TABLE>
   <TR><TD>System:</TD>     <TD>$main::mycall</TD></TR>
   <TR><TD>Maintainer:</TD> <TD>$main::myemail</TD></TR>
   <TR><TD>Description:</TD><TD>Total Users \&amp; Nodes for the Visible Cluster Network </TD></TR>
 </TABLE>
EOF
}

# do the total spots
if ($want{totalspots} || $want{all}) {
	if (open M, ">$dir/totalspots") {
		print M "$Spot::totalspots\n$Spot::totalspots\n$uptime\nTotal Spots\n";
		close M;
	}
	$Spot::totalspots = 0;
	print MC <<"EOF";
#
# total spots
#
Target[totalspots]: `cat /spider/mrtg/totalspots`
MaxBytes[totalspots]: 20000
Title[totalspots]: Total Spots
Options[totalspots]: unknaszero, gauge, withzeroes, growright, nopercent, integer, noi
YLegend[totalspots]: Spots
YTicsFactor[totalspots]: 1
ShortLegend[totalspots]: \&nbsp;
Legend2[totalspots]:Maximum No of Spots
LegendO[totalspots]:Spots
PageTop[totalspots]: <H1>Total Spots</H1>
 <TABLE>
   <TR><TD>System:</TD>     <TD>$main::mycall</TD></TR>
   <TR><TD>Maintainer:</TD> <TD>$main::myemail</TD></TR>
   <TR><TD>Description:</TD><TD>Total Spots</TD></TR>
 </TABLE>
EOF
}

# do the HF and VHF spots
if ($want{hfvhf} || $want{all}) {
	if (open M, ">$dir/hfspots") {
		print M "$Spot::hfspots\n$Spot::vhfspots\n$uptime\nHF and VHF+ Spots\n";
		close M;
	}
	$Spot::hfspots = $Spot::vhfspots = 0;
	print MC <<"EOF";
# 
# HF and VHF spots
#
Target[hfspots]: `cat /spider/mrtg/hfspots`
MaxBytes[hfspots]: 20000
Title[hfspots]: HF and VHF+ Spots
Options[hfspots]: unknaszero, gauge, withzeroes, growright, nopercent, integer
YLegend[hfspots]: Spots
WithPeak[hfspots]: ymwd
YTicsFactor[hfspots]: 1
ShortLegend[hfspots]: \&nbsp;
Legend1[hfspots]:Max no of HF Spots
Legend2[hfspots]:Max no of VHF Spots
LegendI[hfspots]:HF
LegendO[hfspots]:VHF+
PageTop[hfspots]: <H1>Total HF and VHF+ Spots</H1>
 <TABLE>
   <TR><TD>System:</TD>     <TD>$main::mycall</TD></TR>
   <TR><TD>Maintainer:</TD> <TD>$main::myemail</TD></TR>
   <TR><TD>Description:</TD><TD>Total HF and VHF+ Spots</TD></TR>
 </TABLE>
EOF
}

close MC;

my @args;
@args = ("mrtg", $cfg);
system @args;

return (1);
