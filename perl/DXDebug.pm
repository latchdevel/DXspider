#
# The system variables - those indicated will need to be changed to suit your
# circumstances (and callsign)
#
# Copyright (c) 1998 - Dirk Koopman G1TLH
#
#
#

package DXDebug;

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(dbginit dbg dbgadd dbgsub dbglist dbgdump isdbg dbgclose confess croak cluck);

use strict;
use vars qw(%dbglevel $fp $callback $cleandays $keepdays);

use DXUtil;
use DXLog ();
use Carp ();

%dbglevel = ();
$fp = undef;
$callback = undef;
$keepdays = 10;
$cleandays = 100;

# Avoid generating "subroutine redefined" warnings with the following
# hack (from CGI::Carp):
if (!defined $DB::VERSION) {
	local $^W=0;
	eval qq( sub confess { 
	    \$SIG{__DIE__} = 'DEFAULT'; 
        DXDebug::dbg(\$@);
		DXDebug::dbg(Carp::shortmess(\@_));
	    exit(-1); 
	}
	sub croak { 
		\$SIG{__DIE__} = 'DEFAULT'; 
        DXDebug::dbg(\$@);
		DXDebug::dbg(Carp::longmess(\@_));
		exit(-1); 
	}
	sub carp    { DXDebug::dbg(Carp::shortmess(\@_)); }
	sub cluck   { DXDebug::dbg(Carp::longmess(\@_)); } 
	);

    CORE::die(Carp::shortmess($@)) if $@;
} else {
    eval qq( sub confess { die Carp::longmess(\@_); }; 
			 sub croak { die Carp::shortmess(\@_); }; 
			 sub cluck { warn Carp::longmess(\@_); }; 
			 sub carp { warn Carp::shortmess(\@_); }; 
   );
} 


sub dbg($)
{
	return unless $fp;
	my $t = time; 
	for (@_) {
		my $r = $_;
		chomp $r;
		my @l = split /\n/, $r;
		for (@l) {
			s/([\x00-\x08\x0B-\x1f\x7f-\xff])/uc sprintf("%%%02x",ord($1))/eg;
			print "$_\n" if defined \*STDOUT;
			my $str = "$t^$_";
			&$callback($str) if $callback;
			$fp->writeunix($t, $str); 
		}
	}
}

sub dbginit
{
	$callback = shift;
	
	# add sig{__DIE__} handling
	if (!defined $DB::VERSION) {
		$SIG{__WARN__} = sub { 
			if ($_[0] =~ /Deep\s+recursion/i) {
				dbg($@);
				dbg(Carp::longmess(@_)); 
				CORE::die;
			} else { 
				dbg($@);
				dbg(Carp::shortmess(@_));
			}
		};
		
		$SIG{__DIE__} = sub { dbg($@); dbg(Carp::longmess(@_)); };
	}

	$fp = DXLog::new('debug', 'dat', 'd');
}

sub dbgclose
{
	$SIG{__DIE__} = $SIG{__WARN__} = 'DEFAULT';
	$fp->close() if $fp;
	undef $fp;
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
				dbg($m . sprintf("%4d:", $o) . "$h $c");
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

sub isdbg($)
{
	return unless $fp;
	return $dbglevel{$_[0]};
}

sub shortmess 
{
	return Carp::shortmess(@_);
}

sub longmess 
{ 
	return Carp::longmess(@_);
}

# clean out old debug files, stop when you get a gap of more than a month
sub dbgclean
{
	my $date = $fp->unixtoj($main::systime)->sub($keepdays+1);
	my $i = 0;

	while ($i < 31) {
		my $fn = $fp->_genfn($date);
		if (-e $fn) {
			unlink $fn;
			$i = 0;
		} else {
			$i++;
		}
		$date = $date->sub(1);
	}
}

1;
__END__







