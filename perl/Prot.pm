#
# Base class for OO version of all protocol stuff
#

package Prot;

use strict;


use DXUtil;
use DXDebug;
use vars qw(%valid);

%valid = (
		  bellflag => '0,Bell?',
		  datetime => '0,Date/Time,atime',
		  dxcall => '0,DX Callsign',
		  dxcount => '0,DX Count',
		  freq => '0,Frequency',
		  fromcall => '0,From Callsign',
		  fromnode => '0,From Node',
		  hereflag => '0,Here?,yesno',
		  hops => '0,No. of hops',
		  nodelist => '0,Node List,parray',
		  origin => '0,Original Node',
		  privflag => '0,Private?,yesno',
		  rrflag => '0,RR Req.?,yesno',
		  sort => '0,Sort',
		  sysopflag => '0,Sysop flag',
		  talkflag => '0,Talk mode',
		  text => '0,Text',
		  tocall => '0,To Callsign',
		  tonode => '0,To Node',
		  version => '0,Node Version',
		  vianode => '0,Via Node',
		  wwvcount => '0,WWV Count',
		 );


sub new
{
	my $pkg = shift;
	my $sort = shift;
	my $self = bless { sort => $sort }, $pkg;
	return $self;
}

sub AUTOLOAD
{
	no strict;
	my $name = $AUTOLOAD;
	return if $name =~ /::DESTROY$/;
	$name =~ s/^.*:://o;
  
	confess "Non-existant field '$AUTOLOAD'" if !$valid{$name};
	*$AUTOLOAD = sub {@_ > 1 ? $_[0]->{$name} = $_[1] : $_[0]->{$name}};
       goto &$AUTOLOAD;
}

1;
__END__
