#
# This is a local command to generate the various statistics that
# can then be displayed on an MRTG plot
#
# Your mrtg binary must live in one of the standard places
#
# you will need perl 5.6 (probably) to be able to run this command
#

sub cfgprint($$@$$$$$);

my ($self, $line) = @_;

# create the arg list
my %want;
for (split /\s+/, $line) { $want{lc $_} = 1};
			 
return (1, "MRTG not installed") unless $want{test} || -e '/usr/bin/mrtg' || -e '/usr/local/bin/mrtg';

my $dir = "$main::root/mrtg";
my $html = "$main::root/html/mrtg";
my $cfg = "$dir/mrtg.cfg";

my $mc = new IO::File ">$cfg" or return(1, "cannot open $cfg for mrtg writing");

# print out the header
print $mc <<"EOF";
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


#dbg "$dir\n$html\n";
			 
# do the users and nodes
my $users = DXChannel::get_all_users();
my $nodes = DXChannel::get_all_nodes();
my $uptime = main::uptime();
#dbg "$users $nodes $uptime\n";
if (my $m = new IO::File ">$dir/users") {
	print $m "$users\n$nodes\n$uptime\nUsers and Nodes\n";
	close $m;
}
cfgprint($mc, 'users', [qw(gauge)], 500, 
		 "Users and Nodes on $main::mycall",
		 'Users / Nodes', 'Users', 'Nodes');

# do the  total users and nodes
if ($want{totalusers} || $want{all}) {
	$nodes = Route::Node::count();
	$users = Route::User::count();
	#dbg "$users $nodes $uptime\n";
	if (my $m = new IO::File ">$dir/totalusers") {
		print $m "$users\n$nodes\n$uptime\nTotal Users and Nodes\n";
		close $m;
	}
	cfgprint($mc, 'totalusers', [qw(gauge)], 10000, 
			'Total Users and Nodes in the Visible Cluster Network',
			 'Users / Nodes', 'Users', 'Nodes');
}

# do the total spots
if ($want{totalspots} || $want{all}) {
	if (my $m = new IO::File ">$dir/totalspots") {
		print $m "$Spot::totalspots\n$Spot::totalspots\n$uptime\nTotal Spots\n";
		close $m;
	}
	$Spot::totalspots = 0;
	cfgprint($mc, 'totalspots', [qw(unknaszero gauge noi)], 1000, 'Total Spots',
			 'Spots', 'Spots', 'Spots');
}

# do the HF and VHF spots
if ($want{hfvhf} || $want{all}) {
	if (my $m = new IO::File ">$dir/hfspots") {
		print $m "$Spot::hfspots\n$Spot::vhfspots\n$uptime\nHF and VHF+ Spots\n";
		close $m;
	}
	$Spot::hfspots = $Spot::vhfspots = 0;
	cfgprint($mc, 'hfspots', [qw(unknaszero gauge)], 1000, 'HF and VHF+ Spots',
			 'Spots', 'HF', 'VHF');
}

# 
# do the mrtg thing
#
close $mc;
my @out = `mrtg $cfg`;
return (1, @out);

sub cfgprint
{
	my ($mc, $name, $options, $max, $title, $legend, $iname, $oname) = @_;
	my $opt = join ', ', @$options, qw(withzeroes gauge growright nopercent integer);
		
	print $mc <<"EOF";

#
# $title
#

Target[$name]: `cat /spider/mrtg/$name`
MaxBytes[$name]: $max
Title[$name]: $title
Options[$name]: $opt
YLegend[$name]: $legend
YTicsFactor[$name]: 1
ShortLegend[$name]: \&nbsp;
Legend1[$name]:Maximum No of $iname
Legend2[$name]:Maximum No of $oname
LegendI[$name]:$iname
LegendO[$name]:$oname
PageTop[$name]: <H1>$title</H1>
 <TABLE>
   <TR><TD>System:</TD>     <TD>$main::mycall</TD></TR>
   <TR><TD>Maintainer:</TD> <TD>$main::myemail</TD></TR>
   <TR><TD>Description:</TD><TD>$title</TD></TR>
 </TABLE>
EOF

}
