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
@EXPORT = qw(dbginit dbgstore dbg dbgadd dbgsub dbglist dbgdump isdbg dbgclose confess croak cluck cluck);

use strict;
use vars qw(%dbglevel $fp);

use DXUtil;
use DXLog ();
use Carp qw(cluck);

%dbglevel = ();
$fp = undef;

# Avoid generating "subroutine redefined" warnings with the following
# hack (from CGI::Carp):
if (!defined $DB::VERSION) {
	local $^W=0;
	eval qq( sub confess { 
	    \$SIG{__DIE__} = 'DEFAULT'; 
        DXDebug::dbgstore(\$@, Carp::shortmess(\@_));
	    exit(-1); 
	}
	sub croak { 
		\$SIG{__DIE__} = 'DEFAULT'; 
        DXDebug::dbgstore(\$@, Carp::longmess(\@_));
		exit(-1); 
	}
	sub carp    { DXDebug::dbgstore(Carp::shortmess(\@_)); }
	sub cluck   { DXDebug::dbgstore(Carp::longmess(\@_)); } 
	);

    CORE::die(Carp::shortmess($@)) if $@;
} else {
    eval qq( sub confess { Carp::confess(\@_); }; 
	sub cluck { Carp::cluck(\@_); }; 
   );
} 


sub dbgstore
{
	my $t = time; 
	for (@_) {
		my $r = $_;
		chomp $r;
		my @l = split /\n/, $r;
		for (@l) {
			s/([\x00\x08\x0B-\x1f\x7f-\xff])/uc sprintf("%%%02x",ord($1))/eg;
			print "$_\n" if defined \*STDOUT;
			$fp->writeunix($t, "$t^$_"); 
		}
	}
}

sub dbginit
{
	# add sig{__DIE__} handling
	if (!defined $DB::VERSION) {
		$SIG{__WARN__} = sub { dbgstore($@, Carp::shortmess(@_)); };
		$SIG{__DIE__} = sub { dbgstore($@, Carp::longmess(@_)); };
	}

	$fp = DXLog::new('debug', 'dat', 'd');
}

sub dbgclose
{
	$SIG{__DIE__} = $SIG{__WARN__} = 'DEFAULT';
	$fp->close() if $fp;
	undef $fp;
}

sub dbg
{
	my $l = shift;
	if ($fp && ($dbglevel{$l} || $l eq 'err')) {
	    dbgstore(@_);
	}
}

sub dbgdump
{
	my $l = shift;
	my $m = shift;
	if ($fp && ($dbglevel{$l} || $l eq 'err')) {
		foreach my $l (@_) {
			for (my $o = 0; $o < length $l; $o += 16) {
				my $c = substr $l, $o, 16;
				my $h = unpack "H*", $c;
				$c =~ s/[\x00-\x1f\x7f-\xff]/./g;
				my $left = 16 - length $c;
				$h .= ' ' x (2 * $left) if $left > 0;
				dbgstore($m . sprintf("%4d:", $o) . "$h $c");
				$m = ' ' x (length $m);
			}
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

sub shortmess 
{
	return Carp::shortmess(@_);
}

sub longmess 
{ 
	return Carp::longmess(@_);
}

1;
__END__







