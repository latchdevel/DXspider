#
# Search for bad words in strings
#
# Copyright (c) 2000 Dirk Koopman
#
# $Id$
#

package BadWords;

use strict;

use DXUtil;
use DXVars;
use DXHash;
use DXDebug;

use IO::File;

use vars qw($badword $regexcode);

my $oldfn = "$main::data/badwords";
my $regex = "$main::data/badw_regex";
my $bwfn = "$main::data/badword";

# copy issue ones across
filecopy("$regex.gb.issue", $regex) unless -e $regex;
filecopy("$bwfn.issue", $bwfn) unless -e $bwfn;

$badword = new DXHash "badword";

use vars qw($VERSION $BRANCH);
$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /\d+\.\d+\.(\d+)\.(\d+)/ ) || 0;
$main::build += $VERSION;
$main::branch += $BRANCH;

# load the badwords file
sub load
{
	my @out;
	my $fh = new IO::File $oldfn;
	
	if ($fh) {
		while (<$fh>) {
			chomp;
			next if /^\s*\#/;
			my @list = split " ";
			for (@list) {
				$badword->add($_);
			}
		}
		$fh->close;
		$badword->put;
		unlink $oldfn;
	}
	push @out, create_regex(); 
	return @out;
}

sub create_regex
{
	my @out;
	my $fh = new IO::File $regex;
	
	if ($fh) {
		my $s = "sub { my \$str = shift; my \@out; \n";
		while (<$fh>) {
			chomp;
			next if /^\s*\#/;
			my @list = split " ";
			for (@list) {
				# create a closure for each word so that it matches stuff with spaces/punctuation
				# and repeated characters in it
				my $w = uc $_;
				my @l = split //, $w;
				my $e = join '+[\s\W]*', @l;
				$s .= "push \@out, \$1 if \$str =~ /\\b($e)/;\n";
			}
		}
		$s .= "return \@out;\n}";
		$regexcode = eval $s;
		dbg($s) if isdbg('badword');
		if ($@) {
			@out = ($@);
			dbg($@);
			return @out;
		}
		$fh->close;
	} else {
		my $l = "can't open $regex $!";
		dbg($l);
		push @out, $l;
	}
	
	return @out;
}

# check the text against the badwords list
sub check
{
	my $s = uc shift;
	my @out;

	push @out, &$regexcode($s) if $regexcode;
	
	return @out if @out;
	
	for (split(/\s+/, $s)) {
		s/\'?S$//;
		push @out, $_ if $badword->in($_);
	}

	return @out;
}

1;
