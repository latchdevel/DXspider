##
# the MRTG handler
#
# Copyright (c) - 2002 Dirk Koopman G1TLH
#
#
#

package Mrtg;

use IO::File;
use DXVars;
use DXDebug;
use DXUtil;
use strict;

sub new
{
	my $pkg = shift;
	my $class = ref $pkg || $pkg;
	my %args = @_;
	my $self = bless { }, $class;

	# argument processing
	$self->{dir} = $args{dir} || "$main::root/mrtg";
	$self->{html} = $args{html} || "$main::root/html/mrtg";
	$self->{cfg} = $args{cfg} || "$self->{dir}/mrtg.cfg";

	my $mc = new IO::File ">$self->{cfg}" or return undef;
	$self->{mc} = $mc;
	
	# print out the header
	print $mc <<"EOF";
### Global Defaults
Htmldir: $self->{html}
Imagedir: $self->{html}
Logdir: $self->{dir}
Options[_]: growright
Timezone[_]: GMT
##
##
EOF

	return $self;
}

sub run
{
	my $self = shift;
	$self->{mc}->close;
	return `mrtg --lock-file=$self->{dir}/mrtg.lock --confcache-file=$self->{dir}/mrtg.confcache $self->{cfg}`;
}

sub data
{
	my ($self, $name, $vali, $valo, $title) = @_;
	my $uptime = main::uptime();
	$vali ||= 0;
	$valo ||= 0;

	if (my $m = new IO::File ">$self->{dir}/$name" ) {
		$m->print("$vali\n$valo\n$uptime\n$title\n");
		$m->close;
	} else {
		dbg("MRTG: cannot open $self->{dir}/$name $!");
	}
}

sub cfgprint
{
	my ($self, $name, $options, $max, $title, $legend, $iname, $oname) = @_;
	my $opt = join ', ', @$options, qw(withzeroes growright nopercent integer);

	$self->{mc}->print(<<"EOF");

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
1;
