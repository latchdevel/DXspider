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
@EXPORT = qw(dbg dbgadd dbgsub dbglist isdbg);
@EXPORT_OK = qw(dbg dbgadd dbgsub dbglist isdbg);

use strict;
use vars qw(%dbglevel $fp);

use FileHandle;
use DXUtil;
use DXLog ();
use Carp;

%dbglevel = ();
$fp = DXLog::new('debug', 'dat', 'd');

no strict 'refs';

sub dbg
{
	my $l = shift;
	if ($dbglevel{$l}) {
		for (@_) {
			s/\n$//og;
		}
		print "@_\n" if defined \*STDOUT;
		my $t = time;
		$fp->writeunix($t, "$t^@_");
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
		delete $dbglevel{entry};
	}
}

sub dbglist
{
	return keys (%dbglevel);
}

sub isdbg
{
	return $dbglevel{shift};
}
1;
__END__
