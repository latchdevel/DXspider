#
# The system variables - those indicated will need to be changed to suit your
# circumstances (and callsign)
#
# Copyright (c) 1998-2019 - Dirk Koopman G1TLH
#
# Note: Everything is recorded into the ring buffer (in perl terms: a numerically max sized array).
#       To allow debugging of a category (e.g. 'chan') but not onto disc (just into the ring buffer)
#       do: set/debug chan nologchan
#
#       To print the current contents into the debug log: show/debug_ring
#
#       On exit or serious error the ring buffer is printed to the current debug log
#
# In Progress:
#       Expose a localhost listener on port (default) 27755 to things like watchdbg so that they can carry on
#       as normal, possibly with a "remember" button to permanently capture stuff observed.
#
# Future:
#       This is likely to be some form of triggering or filtering controlling (some portion
#       of) ring_buffer dumping.
#
#

package DXDebug;

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(dbginit dbg dbgadd dbgsub dbglist dbgdump isdbg dbgclose confess croak cluck);

use strict;
use vars qw(%dbglevel $fp $callback $cleandays $keepdays $dbgringlth);

use DXUtil;
use DXLog ();
use Carp ();
use POSIX qw(isatty);

%dbglevel = ();
$fp = undef;
$callback = undef;
$keepdays = 10;
$cleandays = 100;
$dbgringlth = 500;

our $no_stdout;					# set if not running in a terminal
our @dbgring;

# Avoid generating "subroutine redefined" warnings with the following
# hack (from CGI::Carp):
if (!defined $DB::VERSION) {
	local $^W=0;
	eval qq( sub confess { 
	    \$SIG{__DIE__} = 'DEFAULT'; 
        DXDebug::dbgprintring() if DXDebug::isdbg('nologchan');
        DXDebug::dbg(\$@);
		DXDebug::dbg(Carp::shortmess(\@_));
	    exit(-1); 
	}
	sub croak { 
		\$SIG{__DIE__} = 'DEFAULT'; 
        DXDebug::dbgprintring() if DXDebug::isdbg('nologchan');
        DXDebug::dbg(\$@);
		DXDebug::dbg(Carp::longmess(\@_));
		exit(-1); 
	}
	sub carp { 
        DXDebug::dbgprintring(25) if DXDebug('nologchan');
        DXDebug::dbg(Carp::shortmess(\@_)); 
    }
	sub cluck { 
        DXDebug::dbgprintring(25) if DXDebug('nologchan');
        DXDebug::dbg(Carp::longmess(\@_)); 
    } );

    CORE::die(Carp::shortmess($@)) if $@;
} else {
    eval qq( sub confess { die Carp::longmess(\@_); }; 
			 sub croak { die Carp::shortmess(\@_); }; 
			 sub cluck { warn Carp::longmess(\@_); }; 
			 sub carp { warn Carp::shortmess(\@_); }; 
   );
} 


my $_isdbg;						# current dbg level we are processing

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
			print "$_\n" if defined \*STDOUT && !$no_stdout;
			my $str = "$t^$_";
			&$callback($str) if $callback;
			if ($dbgringlth) {
				shift @dbgring while (@dbgring > $dbgringlth);
				push @dbgring, $str;
			}
			$fp->writeunix($t, $str) unless $dbglevel{"nolog$_isdbg"}; 
		}
	}
	$_isdbg = '';
}

sub dbginit
{
	$callback = shift;
	
	# add sig{__DIE__} handling
	unless (defined $DB::VERSION) {
		$SIG{__WARN__} = sub { 
			if ($_[0] =~ /Deep\s+recursion/i) {
				dbg($@);
				dbg(Carp::longmess(@_)); 
				CORE::die;
			}
			else { 
				dbg($@);
				dbg(Carp::shortmess(@_));
			}
		};
		
		$SIG{__DIE__} = sub { dbg($@); dbg(Carp::longmess(@_)); };

		# switch off STDOUT printing if we are not talking to a TTY
		unless ($^O =~ /^MS/ || $^O =~ /^OS-2/) {
			unless (isatty(STDOUT->fileno)) {
				++$no_stdout;
			}
		}
	}

	$fp = DXLog::new('debug', 'dat', 'd');
	dbgclearring();
}

sub dbgclose
{
	$SIG{__DIE__} = $SIG{__WARN__} = 'DEFAULT';
	if ($fp) {
		dbgprintring() if grep /nolog/, keys %dbglevel;
		$fp->close();
	}
	dbgclearring();
	undef $fp;
}

sub dbgdump
{
	return unless $fp;
	
	my $l = shift;
	my $m = shift;
	if ($dbglevel{$l} || $l eq 'err') {
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
	if ($dbglevel{$_[0]}) {
		$_isdbg = $_[0];
		return 1;
    }
}

sub shortmess 
{
	return Carp::shortmess(@_);
}

sub longmess 
{
	return Carp::longmess(@_);
}

sub dbgprintring
{
	return unless $fp;
	my $count = shift;
	my $first;
	my $l;
	my $i = defined $count ? @dbgring-$count : 0;
	$count = @dbgring;
	for ( ; $i < $count; ++$i) {
		my ($t, $str) = split /\^/, $dbgring[$i], 2;
		next unless $t;
		my $lt = time;
		unless ($first) {
			$fp->writeunix($lt, "$lt^###");
			$fp->writeunix($lt, "$lt^### RINGBUFFER START at line $i (zero base)");
			$fp->writeunix($lt, "$lt^###");
			$first = $t;
		}
		my $buf = sprintf "%02d:%02d:%02d", (gmtime($t))[2,1,0];
		$fp->writeunix($lt, "$lt^RING: $buf^$str");
	}
	my $et = time;
	$fp->writeunix($et, "$et^###");
	$fp->writeunix($et, "$et^### RINGBUFFER END");
	$fp->writeunix($et, "$et^###");
}

sub dbgclearring
{
	@dbgring = ();
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
		}
		else {
			$i++;
		}
		$date = $date->sub(1);
	}
}

1;
__END__







