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
@EXPORT = qw(dbginit dbg dbgadd dbgsub dbglist isdbg dbgclose confess croak cluck cluck);

use strict;
use vars qw(%dbglevel $fp);

use DXUtil;
use DXLog ();
use Carp qw(cluck);

%dbglevel = ();
$fp = DXLog::new('debug', 'dat', 'd');

# Avoid generating "subroutine redefined" warnings with the following
# hack (from CGI::Carp):
if (!defined $DB::VERSION) {
	local $^W=0;
	eval qq( sub confess { 
	    \$SIG{__DIE__} = 'DEFAULT'; 
        DXDebug::_store(\$@, Carp::shortmess(\@_));
	    exit(-1); 
	}
	sub croak { 
		\$SIG{__DIE__} = 'DEFAULT'; 
        DXDebug::_store(\$@, Carp::longmess(\@_));
		exit(-1); 
	}
	sub carp    { DXDebug::_store(Carp::shortmess(\@_)); }
	sub cluck   { DXDebug::_store(Carp::longmess(\@_)); } 
	);

    CORE::die(Carp::shortmess($@)) if $@;
} else {
    eval qq( sub confess { Carp::confess(\@_); }; 
	sub cluck { Carp::cluck(\@_); }; 
   );
} 


sub _store
{
	my $t = time; 
	for (@_) {
		chomp;
		my @l = split /\n/;
		for (@l) {
			my $l = $_;
			$l =~ s/([\x00\x08\x0B-\x1f\x7f-\xff])/uc sprintf("%%%02x",ord($1))/eg;			
			print "$_\n" if defined \*STDOUT;
			$fp->writeunix($t, "$t^$_"); 
		}
	}
}

sub dbginit
{
	# add sig{__DIE__} handling
	if (!defined $DB::VERSION) {
		$SIG{__WARN__} = sub { _store($@, Carp::shortmess(@_)); };
		$SIG{__DIE__} = sub { _store($@, Carp::longmess(@_)); };
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
	if ($dbglevel{$l} || $l eq 'err') {
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







