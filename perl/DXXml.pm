#
# XML handler
#
# $Id$
#
# Copyright (c) Dirk Koopman, G1TLH
#

use strict;

package DXXml;
use IsoTime;

use DXProt;
use DXDebug;
use DXLog;
use DXXml::Ping;
use DXXml::Dx;

use vars qw($VERSION $BRANCH $xs $id);
$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /\d+\.\d+\.(\d+)\.(\d+)/  || (0,0));
$main::build += $VERSION;
$main::branch += $BRANCH;

$xs = undef;					# the XML::Simple parser instance
$id = 0;						# the next ID to be used

# generate a new XML sentence structure 
sub new
{
	my $pkg = shift;
	my $class = ref $pkg || $pkg;
	return bless{@_}, $class;
}

#
# note that this a function not a method
#
sub init
{
	return unless $main::do_xml;
	
	eval { require XML::Simple; };
	unless ($@) {
		import XML::Simple;
		$DXProt::handle_xml = 1;
		$xs = new XML::Simple();
	}
	undef $@;
}

#
# note that this a function not a method
#
sub normal
{
	my $dxchan = shift;
	my $line = shift;

	unless ($main::do_xml) {
		dbg("xml not enabled, IGNORED") if isdbg('chanerr');
		return;
	}
	
	my ($rootname) = $line =~ '<(\w+) ';
	my $pkg = "DXXml::" . ucfirst lc "$rootname";

	unless (defined *{"${pkg}::"} && $pkg->can('handle_input')) {
		dbg("xml sentence $rootname not recognised, IGNORED") if isdbg('chanerr');
		return;
	}
		
	my $xref;
	unless ($xref = $pkg->decode_xml($dxchan, $line))  {
		dbg("invalid XML ($@), IGNORED") if isdbg('chanerr');
		undef $@;
		return;
	}
	
	# mark the handle as accepting xml (but only if they 
	# have at least one right)
	$dxchan->handle_xml(1);

	$xref = bless $xref, $pkg;
	$xref->{'-xml'} = $line; 
	$xref->handle_input($dxchan);
}

#
# note that this a function not a method
#
sub process
{

}

sub decode_xml
{
	my $pkg = shift;
	my $dxchan = shift;
	my $line = shift;

	my $xref;
	eval {$xref = $xs->XMLin($line)};
	return $xref;
}

sub nextid
{
	my $r = $id++;
	$id = 0 if $id > 999;
	return $r;
}

sub toxml
{
	my $self = shift;

	unless (exists $self->{'-xml'}) {
		$self->{o} ||= $main::mycall;
		$self->{t} ||= IsoTime::dayms();
		$self->{id} ||= nextid();
		
		my ($name) = ref $self =~ /::(\w+)$/;
		$self->{'-xml'} = $xs->XMLout($self, RootName =>lc $name, NumericEscape=>1);
	}
	return $self->{'-xml'};
}

sub route
{
	my $self = shift;
	my $fromdxchan = shift;
	my $to = shift;
	my $via = $to || $self->{'-via'} || $self->{to};

	unless ($via) {
		dbg("XML: no route specified (" . $self->toxml . ")") if isdbg('chanerr');
		return;
	}
	if (ref $fromdxchan && $via && $fromdxchan->call eq $via) {
		dbg("XML: Trying to route back to source (" . $self->toxml . ")") if isdbg('chanerr');
		return;
	}

	# always send it down the local interface if available
	my $dxchan = DXChannel::get($via);
	if ($dxchan) {
		dbg("route: $via -> $dxchan->{call} direct" ) if isdbg('route');
	} else {
		my $cl = Route::get($via);
		$dxchan = $cl->dxchan if $cl;
		dbg("route: $via -> $dxchan->{call} using normal route" ) if isdbg('route');
	}

	# try the backstop method
	unless ($dxchan) {
		my $rcall = RouteDB::get($via);
		if ($rcall) {
			$dxchan = DXChannel::get($rcall);
			dbg("route: $via -> $rcall using RouteDB" ) if isdbg('route') && $dxchan;
		}
	}
	
	unless ($dxchan) {
		dbg("XML: no route available to $via") if isdbg('chanerr');
		return;
	}

	if ($fromdxchan->call eq $via) {
		dbg("XML: Trying to route back to source (" . $self->toxml . ")") if isdbg('chanerr');
		return;
	}

	if ($dxchan == $main::me) {
		dbg("XML: Trying to route to me (" . $self->toxml . ")") if isdbg('chanerr');
		return;
	}

	if ($dxchan->handle_xml) {
		$dxchan->send($self->toxml);
	} else {
		$self->{o} ||= $main::mycall;
		$self->{id} ||= nextid();
		$self->{'-timet'} ||= $main::systime;
		$dxchan->send($self->topcxx);
	}
}

sub has_xml
{
	return exists $_[0]->{'-xml'};
}

sub has_pcxx
{
	return exists $_[0]->{'-pcxx'};
}

sub has_cmd
{
	return exists $_[0]->{'-cmd'};
}

1;
