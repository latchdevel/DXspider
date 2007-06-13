#
# Base class for OO version of all protocol stuff
#

package Prot;

use strict;


use DXUtil;
use DXDebug;
use vars qw(%valid);

%valid = (
		  fromnode => '0,From Node',
		  tonode => '0,To Node',
		  vianode => '0,Via Node',
		  origin => '0,Original Node',
		  tocall => '0,To Callsign',
		  fromcall => '0,From Callsign',
		  hops => '0,No. of hops',
		  text => '0,Text',
		  datetime => '0,Date/Time,atime',
		  freq => '0,Frequency',
		  dxcall => '0,DX Callsign',
		  sort => '0,Sort',
		  hereflag => '0,Here?,yesno',
		  talkflag => '0,Talk mode',
		  bellflag => '0,Bell?',
		  privflag => '0,Private?,yesno',
		  rrflag => '0,RR Req.?,yesno',
		  sysopflag => '0,Sysop flag',
		  dxcount => '0,DX Count',
		  wwvcount => '0,WWV Count',
		  version => '0,Node Version',
		  nodelist => '0,Node List,parray',
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
