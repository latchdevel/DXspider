#
# The system variables - those indicated will need to be changed to suit your
# circumstances (and callsign)
#
# Copyright (c) 1998 - Dirk Koopman G1TLH
#
# $Id$
#

package DXDebug;

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(dbginit dbg dbgadd dbgsub dbglist isdbg dbgclose);
@EXPORT_OK = qw(dbginit dbg dbgadd dbgsub dbglist isdbg dbgclose);

use strict;
use vars qw(%dbglevel $fp);

use DXUtil;
use DXLog ();
use Carp;

%dbglevel = ();
$fp = DXLog::new('debug', 'dat', 'd');

sub _store
{
	my $t = time; 
	for (@_) {
		$fp->writeunix($t, "$t^$_"); 
		print STDERR $_;
	}
}

sub dbginit
{
	# add sig{__DIE__} handling
	if (!defined $DB::VERSION) {
		$SIG{__WARN__} = $SIG{__DIE__} = \&_store;
	}
}

sub dbgclose
{
	$SIG{__DIE__} = $SIG{__WARN__} = 'DEFAULT';
	$fp->close();
}

sub dbg
{
	my $l = shift;
	if ($dbglevel{$l}) {
	    my @in = @_;
		my $t = time;
		for (@in) {
		    s/\n$//o;
			s/\a//og;   # beeps
			print "$_\n" if defined \*STDOUT;
			$fp->writeunix($t, "$t^$_");
		}
	}
}

sub dbgadd
{ 
	my $entry;
	
	foreach $entry (@_) {
		$dbglevel{$entry} = 1;
	}
}

sub dbgsub
{
	my $entry;
	
	foreach $entry (@_) {
		delete $dbglevel{$entry};
	}
}

sub dbglist
{
	return keys (%dbglevel);
}

sub isdbg
{
	my $s = shift;
	return $dbglevel{$s};
}
1;
__END__
