#!/usr/bin/perl -w

# cat Commands_en.hlp | ./commands2sgml.pl <level> > commands.sgml
# Level 0 is assumed by default.

# This Perl may not be nice but it seems to work :)
# This is supposed to take a spider command definition file and
# convert it to SGML format suitable for inclusion in the spider manual.
#
# It is cunningly written with no language in mind, and should work for all
# command files in whatever language.  
#
# I claim no suitability for purpose, and should this script mutate and eat
# your children I'm afraid I'm not responsible.  Wild herds of rampaging
# Taiwanese suicide squirrels attacking your rabbit are also not my fault.
#
# Ian (M0AZM) 20030210.
#
# $Id$
#

print STDERR localtime() ." ($$) $0 Starting\n";

use strict;

# Bewitched, debugged and bewildered?
my $DEBUG = 0 ;

# SGML headers - use for debugging your SGML output :)
my $HEADERS = 0 ;

# Definitions of things....
my $count = 0 ;
my ($cmd, $line) ;
my %help ;

# Default output level, take $ARGV[0] as being a level
my $level = shift || 0 ;

# Disable line buffering
$| = 1 ;

# SGML headers
if ($HEADERS) {
    print("<!doctype linuxdoc system>\n") ;
    print("<article>\n") ;
    print("<sect>\n") ;
}

# Loop until EOF
while (<>) {

    # Ignore comments
    next if /^\s*\#/;

	chomp $_;
    
	# Is this a command definition line?
	# if(m/^=== ([\d])\^([\w,\W]*)\^([\w,\W]*)/)
	if (/^=== ([\d])\^(.*)\^(.*)/) {
		$count++ ;
        
		if ($DEBUG) {
			print("Level       $1\n") ;
			print("Command     $2\n") ;
			print("Description $3\n") ;
			next;
		}

		$cmd = $2 ;

		$help{$cmd}{level} = $1 ;
		$help{$cmd}{command} = $2 ;
		$help{$cmd}{description} = $3 ;
	} else {
		# Not a command definition line - Carry On Appending(tm)....
		$help{$cmd}{comment} .= $_ . "\n" ;
	}
	# print("$_\n") ;
}

# Go through all of the records in the hash in order
foreach $cmd (sort(keys %help)) {

	# Level checking goes here.
	next if $help{$cmd}{level} > $level;
    
	# Need to change characters that SGML doesn't like at this point.
	# Perhaps we should use a function for each of these variables?
	# Deal with < and >
	$help{$cmd}{command} =~ s/</&lt;/g ;
	$help{$cmd}{command} =~ s/>/&gt;/g ;

	# Deal with [ and ]
	$help{$cmd}{command} =~ s/\[/&lsqb;/g ;
	$help{$cmd}{command} =~ s/\]/&rsqb;/g ;

	# Change to lower case
	$help{$cmd}{command} = lc($help{$cmd}{command}) ;

	# Deal with < and >
	$help{$cmd}{description} =~ s/</&lt;/g ;
	$help{$cmd}{description} =~ s/>/&gt;/g ;

	# Deal with < and >
	if ($help{$cmd}{comment}) {
		$help{$cmd}{comment} =~ s/</&lt;/g ;
		$help{$cmd}{comment} =~ s/>/&gt;/g ;
	}

	# Output the section details and command summary.
	print("<sect1>$help{$cmd}{command}") ;
	print(" ($help{$cmd}{level})") if $level > 0;
	print("\n\n") ;
	print("<P>\n") ;
	print("<tt>\n") ;
	print("<bf>$help{$cmd}{command}</bf> $help{$cmd}{description}\n") ;
	print("</tt>\n") ;
	print("\n") ;

	# Output the command comments.
	print("<P>\n") ;

	# Loop through each line of the command comments.
	# If the first character of the line is whitespace, then use tscreen
	# Once a tscreen block has started, continue until the next blank line.
	my $block = 0 ;

	# Is the comment field blank?  Then trying to split will error - lets not.
	next unless $help{$cmd}{comment};

	# Work through the comments line by line
	foreach $line (split('\n', $help{$cmd}{comment})) {
		# Leading whitespace or not?
		if ($line =~ /^\s+\S+/) {
			if (!$block) {
				$block = 1 ;
				print("<tscreen><verb>\n") ; 
			}
		} else {
			if ($block) {
				$block = 0 ;
				print("</verb></tscreen>\n") ;
			}
		}
		print("$line\n") ;
	}
    
	# We fell out of the command comments still in a block - Ouch....
	if ($block) {
		print("</verb></tscreen>\n\n") ;
	}
}

print("</article>\n") ;

# Is it 'cos we is dun ?
print STDERR localtime()." ($$) $0 Exiting ($count read)\n" ;

