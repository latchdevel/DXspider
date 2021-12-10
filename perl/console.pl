#!/usr/bin/perl -w
#
# this is the operators console.
#
# Calling syntax is:-
#
# console.pl [callsign] 
#
# if the callsign isn't given then the sysop callsign in DXVars.pm is assumed
#
# Copyright (c) 1999 Dirk Koopman G1TLH
#
#
# 

require 5.004;
package main;

use vars qw($data $clusteraddr $clusterport);

$clusteraddr = '127.0.0.1';     # cluster tcp host address - used for things like console.pl
$clusterport = 27754;           # cluster tcp port

# search local then perl directories
BEGIN {
	# root of directory tree for this system
	$root = "/spider"; 
	$root = $ENV{'DXSPIDER_ROOT'} if $ENV{'DXSPIDER_ROOT'};
	
	unshift @INC, "$root/perl";	# this IS the right way round!
	unshift @INC, "$root/local";
	$is_win = ($^O =~ /^MS/ || $^O =~ /^OS-2/) ? 1 : 0; # is it Windows?
	$data = "$root/data";
}

use Msg;
use IntMsg;
use DXVars;
use DXDebug;
use DXUtil;
use DXDebug;
use IO::File;
use Time::HiRes qw(gettimeofday tv_interval);
use Curses 1.06;
use Text::Wrap;

use Console;

#
# initialisation
#

$call = "";                     # the callsign being used
$node = "";                     # the node callsign being used

$conn = 0;                      # the connection object for the cluster
$lasttime = time;               # lasttime something happened on the interface

$connsort = "local";
@kh = ();
@sh = ();
$khistpos = 0;
$spos = $pos = $lth = 0;
$inbuf = "";
@time = ();

#$SIG{WINCH} = sub {@time = gettimeofday};

sub mydbg
{
	local *STDOUT = undef;
	dbg(@_);
}

# do the screen initialisation
sub do_initscr
{
	$scr = new Curses;
	if ($has_colors) {
		start_color();
		init_pair("0", $foreground, $background);
#		init_pair(0, $background, $foreground);
		init_pair(1, COLOR_RED, $background);
		init_pair(2, COLOR_YELLOW, $background);
		init_pair(3, COLOR_GREEN, $background);
		init_pair(4, COLOR_CYAN, $background);
		init_pair(5, COLOR_BLUE, $background);
		init_pair(6, COLOR_MAGENTA, $background);
		init_pair(7, COLOR_RED, COLOR_BLUE);
		init_pair(8, COLOR_YELLOW, COLOR_BLUE);
		init_pair(9, COLOR_GREEN, COLOR_BLUE);
		init_pair(10, COLOR_CYAN, COLOR_BLUE);
		init_pair(11, COLOR_BLUE, COLOR_RED);
		init_pair(12, COLOR_MAGENTA, COLOR_BLUE);
		init_pair(13, COLOR_YELLOW, COLOR_GREEN);
		init_pair(14, COLOR_RED, COLOR_GREEN);
		eval { assume_default_colors($foreground, $background) } unless $is_win;
	}

	$top = $scr->subwin($lines-4, $cols, 0, 0);
	$top->intrflush(0);
	$top->scrollok(1);
	$top->idlok(1);
	$top->meta(1);
#	$scr->addstr($lines-4, 0, '-' x $cols);
	$bot = $scr->subwin(3, $cols, $lines-3, 0);
	$bot->intrflush(0);
	$bot->scrollok(1);
	$top->idlok(1);
	$bot->keypad(1);
	$bot->move(1,0);
	$bot->meta(1);
	$bot->nodelay(1);
	$scr->refresh();
	
	$pagel = $lines-4;
	$mycallcolor = COLOR_PAIR(1) unless $mycallcolor;
}

sub do_resize
{
	endwin() if $scr;
	initscr();
	raw();
	noecho();
	nonl();
 	$lines = LINES;
	$cols = COLS;
	$has_colors = has_colors();
	do_initscr();
	$inscroll = 0;
	$spos = @sh < $pagel ? 0 :  @sh - $pagel;
	show_screen();
	$conn->send_later("C$call|$cols") if $conn;
	
}

# cease communications
sub cease
{
	my $sendz = shift;
	$conn->disconnect if $conn;
	endwin();
	dbgclose();
	print @_ if @_;
	exit(0);	
}

# terminate program from signal
sub sig_term
{
	cease(1, @_);
}

# determine the colour of the line
sub setattr
{
	if ($has_colors) {
		foreach my $ref (@colors) {
			if ($_[0] =~ m{$$ref[0]}) {
				$top->attrset($$ref[1]);
				last;
			}
		}
	}
}


# display the top screen
sub show_screen
{	if ($inscroll) {
		
		dbg("B: s:$spos h:" . scalar @sh) if isdbg('console');
		my ($i, $l);

		$spos = 0 if $spos < 0;
		my $y = $spos;
		$top->move(0, 0);
		$top->attrset(COLOR_PAIR(0)) if $has_colors;
		$top->clrtobot();
		for ($i = 0; $i < $pagel && $y < @sh; ++$y) {
			my $line = $sh[$y];
			my $lines = 1;
			$top->move($i, 0);
			dbg("C: s:$spos y:$i sh:" . scalar @sh . " l:" . length($line) . " '$line'") if isdbg('console');
			setattr($line);
			$top->addstr($line);
			$top->attrset(COLOR_PAIR(0)) if $has_colors;
			$i += $lines;
		}
		if ($y >= @sh) {
			$inscroll = 0;
			$spos = @sh;
		}
	}	elsif ($spos < @sh || $spos < $pagel) {
		# if we really are scrolling thru at the end of the history
		while ($spos < @sh) {
			my $line = $sh[$spos];
			my $y = $spos;
			if ($y >= $pagel) {
				$top->scrollok(1);
				$top->scrl(1);
				$top->scrollok(0);
				$y = $pagel-1;
			}
			$top->move($y, 0);
			dbg("A: s:$spos sh:" . scalar @sh . " y:$y l:" . length($line) . " '$line'") if isdbg('console');
			$top->refresh;
			setattr($line);
			$line =~ s/\n//s;
			$top->addstr($line);
			$top->attrset(COLOR_PAIR(0)) if $has_colors;
			++$spos;
		}
		shift @sh while @sh > $maxshist;
		$spos = @sh;
	}

	$top->refresh;
    my $shl = @sh;
	my $size = $lines . 'x' . $cols . '-'; 
	my $add = "-$spos-$shl";
    my $time = ztime(time);
	my $c = "$call\@$node";
	my $str =  "-" . $time . '-' . ($inscroll ? 'S':'-') . '-' x ($cols - (length($size) + length($c) + length($add) + length($time) + 3));
	$scr->addstr($lines-4, 0, $str);
	
	$scr->addstr($size);
	$scr->attrset($mycallcolor) if $has_colors;
	$scr->addstr($c);
	$scr->attrset(COLOR_PAIR(0)) if $has_colors;
    $scr->addstr($add);
	$scr->refresh();
#	$top->refresh();
}

# add a line to the end of the top screen
sub addtotop
{
	while (@_) {
		my $inbuf = shift;
		my $l = length $inbuf;
		if ($l > $cols) {
			$inbuf =~ s/\s+/ /g;
			if (length $inbuf > $cols) {
				$Text::Wrap::columns = $cols;
				my $token;
				($token) = $inbuf =~ m!^(.* de [-\w\d/\#]+\s+|\w{9}\@\d\d:\d\d:\d\d )!;
				$token ||= ' ' x 19;
				push @sh, split /\n/, wrap('', ' ' x length($token), $inbuf);
			} else {
				push @sh, $inbuf;
			}
		} else {
			push @sh, $inbuf;
		}
	}
#	shift @sh while @sh > $maxshist;
	show_screen();
}

# handle incoming messages
sub rec_socket
{
	my ($con, $msg, $err) = @_;
	if (defined $err && $err) {
		cease(1);
	}
	if (defined $msg) {
		my ($sort, $incall, $line) = $msg =~ /^(\w)([^\|]+)\|(.*)$/;
		if ($line =~ s/\x07+$//) {
			beep();
		}
		$line =~ s/[\r\n]+//s;

		# change my call if my node says "tonight Michael you are Jane" or something like that...
		$call = $incall if $call ne $incall;
		
		$line =~ s/[\x00-\x06\x08\x0a-\x19\x1b-\x1f\x80-\x9f]/./g;         # immutable CSI sequence + control characters
		if ($sort && $sort eq 'D') {
			$line = " " unless length($line);
			addtotop($line);
		} elsif ($sort && $sort eq 'Z') { # end, disconnect, go, away .....
			cease(0);
		}	  
		
		# ******************************************************
		# ******************************************************
		# any other sorts that might happen are silently ignored.
		# ******************************************************
		# ******************************************************
	} else {
		cease(0);
	}
	$top->refresh();
	$lasttime = time; 
}

sub rec_stdin
{
	my $r = shift;;
	
	#  my $prbuf;
	#  $prbuf = $buf;
	#  $prbuf =~ s/\r/\\r/;
	#  $prbuf =~ s/\n/\\n/;
	#  print "sys: $r ($prbuf)\n";
	if (defined $r) {

		$r = '0' if !$r;
		
		if ($r eq KEY_ENTER || $r eq "\n" || $r eq "\r") {
			
			# save the lines
			$inbuf = " " unless length $inbuf;

			# check for a pling and do a search back for a command
			if ($inbuf =~ /^!/o) {
				my $i;
				$inbuf =~ s/^!//o;
				for ($i = $#kh; $i >= 0; $i--) {
					if ($kh[$i] =~ /^$inbuf/) {
						$inbuf = $kh[$i];
						last;
					}
				}
				if ($i < 0) {
					beep();
					return;
				}
			}
			push @kh, $inbuf if length $inbuf;
			shift @kh if @kh > $maxkhist;
			$khistpos = @kh;
			$bot->move(0,0);
			$bot->clrtoeol();
			$bot->addstr(substr($inbuf, 0, $cols));

			if ($inscroll && $spos < @sh) {
				$spos = @sh - $pagel;
				$inscroll = 0;
				show_screen();
			}

			# add it to the monitor window
			addtotop($inbuf);
		
			# send it to the cluster
			$conn->send_later("I$call|$inbuf");
			$inbuf = "";
			$pos = $lth = 0;
		} elsif ($r eq KEY_UP || $r eq "\020") {
			if ($khistpos > 0) {
				--$khistpos;
				$inbuf = $kh[$khistpos];
				$pos = $lth = length $inbuf;
			} else {
				beep();
			}
		} elsif ($r eq KEY_DOWN || $r eq "\016") {
			if ($khistpos < @kh - 1) {
				++$khistpos;
				$inbuf = $kh[$khistpos];
				$pos = $lth = length $inbuf;
			} else {
				beep();
			}
		} elsif ($r eq KEY_PPAGE || $r eq "\032") {
			if ($spos > 0 && @sh > $pagel) {
				$spos -= $pagel+int($pagel/2); 
				$spos = 0 if $spos < 0;
				$inscroll = 1;
				show_screen();
			} else {
				beep();
			}
		} elsif ($r eq KEY_NPAGE || $r eq "\026") {
			if ($inscroll && $spos < @sh) {

				$spos += int($pagel/2);
				if ($spos > @sh - $pagel) {
					$spos = @sh - $pagel;
				} 
				show_screen();
				if ($spos >= @sh) {
					$spos = @sh;
					$inscroll = 0;
				}
			} else {
				beep();
			}
		} elsif ($r eq KEY_LEFT || $r eq "\002") {
			if ($pos > 0) {
				--$pos;
			} else {
				beep();
			}
		} elsif ($r eq KEY_RIGHT || $r eq "\006") {
			if ($pos < $lth) {
				++$pos;
			} else {
				beep();
			}
		} elsif ($r eq KEY_HOME || $r eq "\001") {
			$pos = 0;
		} elsif ($r eq KEY_END || $r eq "\005") {
			$pos = $lth;
		} elsif ($r eq KEY_BACKSPACE || $r eq "\010" || $r eq "\x7f") {
			if ($pos > 0) {
				my $a = substr($inbuf, 0, $pos-1);
				my $b = substr($inbuf, $pos) if $pos < $lth;
				$b = "" unless $b;
				
				$inbuf = $a . $b;
				--$lth;
				--$pos;
			} else {
				beep();
			}
		} elsif ($r eq KEY_DC || $r eq "\004") {
			if ($pos < $lth) {
				my $a = substr($inbuf, 0, $pos);
				my $b = substr($inbuf, $pos+1) if $pos < $lth;
				$b = "" unless $b;
				
				$inbuf = $a . $b;
				--$lth;
			} else {
				beep();
			}
		} elsif ($r eq KEY_RESIZE || $r eq "\0632") {
			do_resize();
			return;
		} elsif (defined $r && is_pctext($r)) {
			# move the top screen back to the bottom if you type something
			if ($spos < @sh) {
				$spos = @sh;
				show_screen();
			}

		#	$r = ($r lt ' ' || $r gt "\x7e") ? sprintf("'%x", ord $r) : $r;
			
			# insert the character into the keyboard buffer
			if ($pos < $lth) {
				my $a = substr($inbuf, 0, $pos);
				my $b = substr($inbuf, $pos);
				$inbuf = $a . $r . $b;
			} else {
				$inbuf .= $r;
			}
			$pos++;
			$lth++;
		} elsif ($r eq "\014" || $r eq "\022") {
			touchwin(curscr, 1);
			refresh(curscr);
			return;
		} elsif ($r eq "\013") {
			$inbuf = substr($inbuf, 0, $pos);
			$lth = length $inbuf;
		} else {
			beep();
		}
		$bot->move(1, 0);
		$bot->clrtobot();
		$bot->addstr($inbuf);
	} 
	$bot->move(1, $pos);
	$bot->refresh();
}


#
# deal with args
#

$call = uc shift @ARGV if @ARGV;
$call = uc $myalias if !$call;
$node = uc $mycall unless $node;

my ($scall, $ssid) = split /-/, $call;
$ssid = undef unless $ssid && $ssid =~ /^\d+$/;  
if ($ssid) {
	$ssid = 15 if $ssid > 15;
	$call = "$scall-$ssid";
}

if ($call eq $mycall) {
	print "You cannot connect as your cluster callsign ($mycall)\n";
	exit(0);
}

dbginit();

$conn = IntMsg->connect("$clusteraddr", $clusterport, \&rec_socket);
if (! $conn) {
	if (-r "$data/offline") {
		open IN, "$data/offline" or die;
		while (<IN>) {
			print $_;
		}
		close IN;
	} else {
		print "Sorry, the cluster $mycall is currently off-line\n";
	}
	exit(0);
}

$conn->set_error(sub{cease(0)});


unless ($DB::VERSION) {
	$SIG{'INT'} = \&sig_term;
	$SIG{'TERM'} = \&sig_term;
}

$SIG{'HUP'} = \&sig_term;

# start up
do_resize();

$SIG{__DIE__} = \&sig_term;

$conn->send_later("A$call|$connsort width=$cols");
$conn->send_later("I$call|set/page $maxshist");
$conn->send_later("I$call|set/nobeep");

#Msg->set_event_handler(\*STDIN, "read" => \&rec_stdin);

$Text::Wrap::columns = $cols;

my $lastmin = 0;
for (;;) {
	my $t;
	Msg->event_loop(1, 0.01);
	$t = time;
	if ($t > $lasttime) {
		my ($min)= (gmtime($t))[1];
		if ($min != $lastmin) {
			show_screen();
			$lastmin = $min;
		}
		$lasttime = $t;
	}
	my $ch = $bot->getch();
	if (@time && tv_interval(\@time, [gettimeofday]) >= 1) {
		next;
	}
	if (defined $ch) {
		if ($ch ne '-1') {
			rec_stdin($ch);
		}
	}
	$top->refresh() if $top->is_wintouched;
	$bot->refresh();
}

exit(0);
