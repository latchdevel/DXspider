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
@EXPORT = qw(dbginit dbg dbgadd dbgsub dbglist isdbg);

use strict;
use vars qw(%dbglevel $dbgfh);

use FileHandle;
use DXUtil;

%dbglevel = ();
$dbgfh = "";

no strict 'refs';

sub dbginit
{
  my $fhname = shift;
  $dbgfh = new FileHandle;
  $dbgfh->open(">>$fhname") or die "can't open debug file '$fhname' $!";
  $dbgfh->autoflush(1);
}

sub dbg
{
  my $l = shift;
  if ($dbglevel{$l}) {
    print @_;
	print $dbgfh atime, @_ if $dbgfh;
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
