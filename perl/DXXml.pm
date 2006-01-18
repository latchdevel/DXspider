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
use DXUtil;
use DXXml::Ping;
use DXXml::Dx;
use DXXml::IM;

use vars qw($VERSION $BRANCH $xs $id $max_old_age $max_future_age $dupeage);
$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /\d+\.\d+\.(\d+)\.(\d+)/  || (0,0));
$main::build += $VERSION;
$main::branch += $BRANCH;

$xs = undef;					# the XML::Simple parser instance
$id = 0;						# the next ID to be used
$max_old_age = 3600;			# how old a sentence we will accept
$max_future_age = 900;			# how far into the future we will accept
$dupeage = 12*60*60;			# duplicates stored half a day 


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
	
	eval { require XML::Simple };
	eval { require XML::Parser } unless $@;
	if ($@) {
		LogDbg('err', "do_xml was set to 1 and the XML routines failed to load ($@)");
		$main::do_xml = 0;
	} else {
		$XML::Simple::PREFERRED_PARSER = 'XML::Parser';
		import XML::Simple;
		$DXProt::handle_xml = 1;
		$xs = new XML::Simple(Cache=>[]);
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

	# do some basic checks
	my ($o, $t, $id);
	unless (exists $xref->{o} && is_callsign($o = $xref->{o})) {
		dbg("Invalid origin, not a callsign") if isdbg('chanerr');
		return;
	}
	unless (exists $xref->{t} && ($t = IsoTime::unixtime($xref->{t}))) {
		dbg("Invalid, non-existant or zero time") if isdbg('chanerr');
		return;
	}
	unless ($t < $main::systime - $max_old_age || $t > $main::systime + $max_future_age) {
		dbg("Too old or too far in the future") if isdbg('chanerr');
		return;
	}
	unless (exists $xref->{id} && ($id = $xref->{id}) >= 0 && $id <= 9999) {
		dbg("Invalid or non-existant id") if isdbg('chanerr');
		return;
	}

	# mark the handle as accepting xml (but only if they 
	# have at least one right)
	$dxchan->handle_xml(1);

	# now check that we have not seen this before 
	# this is based on the tuple (o (origin), t (time, normalised to time_t), id)
	$xref->{'-timet'} = $t;
	return if DXDupe::check("xml,$o,$t,$id", $dupeage);
		
	$xref = bless $xref, $pkg;
	$xref->{'-xml'} = $line; 
	$xref->handle_input($dxchan);
}

#
# note that this a function not a method
#

my $last10;
my $last_hour;

sub process
{
	my $t = time;
	my @dxchan = DXChannel::get_all();
	my $dxchan;

	foreach $dxchan (@dxchan) {
		next unless $dxchan->is_node;
		next unless $dxchan->handle_xml;
		next if $dxchan == $main::me;

		# send a ping out on this channel
		if ($dxchan->{pingint} && $t >= $dxchan->{pingint} + $dxchan->{lastping}) {
			if ($dxchan->{nopings} <= 0) {
				$dxchan->disconnect;
			} else {
				DXXml::Ping::add($main::me, $dxchan->call);
				$dxchan->{nopings} -= 1;
				$dxchan->{lastping} = $t;
				$dxchan->{lastping} += $dxchan->{pingint} / 2 unless @{$dxchan->{pingtime}};
			}
		}
	}


	# every ten seconds
	if (!$last10 || $t - $last10 >= 10) {	
		$last10 = $t;
	}

	# every hour
	if (!$last_hour || $main::systime - 3600 > $last_hour) {
		$last_hour = $main::systime;
	}

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
		$self->{t} ||= IsoTime::dayminsec();
		$self->{id} ||= nextid();
		
		my ($name) = (ref $self) =~ /::(\w+)$/;
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
