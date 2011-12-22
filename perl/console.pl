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

# search local then perl directories
BEGIN {
	# root of directory tree for this system
	$root = "/spider"; 
	$root = $ENV{'DXSPIDER_ROOT'} if $ENV{'DXSPIDER_ROOT'};
	
	unshift @INC, "$root/perl";	# this IS the right way round!
	unshift @INC, "$root/local";
	$is_win = ($^O =~ /^MS/ || $^O =~ /^OS-2/) ? 1 : 0; # is it Windows?
}

use strict;

use AnyEvent;
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

use vars qw($maxkhist $maxshist $foreground	$background $mycallcolor @colors );

#
# initialisation
#

my $call = "";                     # the callsign being used
my $conn = 0;                      # the connection object for the cluster
my $lasttime = time;               # lasttime something happened on the interface

my $connsort = "local";
my @khistory = ();
my @shistory = ();
my $khistpos = 0;
my $pos;
my $lth;
my $bot;
my $top;
my $pagel = 25;
my $cols = 80;
my $lines = 25;
my $scr;
my $spos = $pos = $lth = 0;
my $inbuf = "";
my @time = ();

my $lastmin = 0;
my $sigint;
my $sigterm;
my $decease;

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
	if ($main::has_colors) {
		start_color();
		init_pair("0", $main::foreground, $main::background);
#		init_pair(0, $main::background, $main::foreground);
		init_pair(1, COLOR_RED, $main::background);
		init_pair(2, COLOR_YELLOW, $main::background);
		init_pair(3, COLOR_GREEN, $main::background);
		init_pair(4, COLOR_CYAN, $main::background);
		init_pair(5, COLOR_BLUE, $main::background);
		init_pair(6, COLOR_MAGENTA, $main::background);
		init_pair(7, COLOR_RED, COLOR_BLUE);
		init_pair(8, COLOR_YELLOW, COLOR_BLUE);
		init_pair(9, COLOR_GREEN, COLOR_BLUE);
		init_pair(10, COLOR_CYAN, COLOR_BLUE);
		init_pair(11, COLOR_BLUE, COLOR_RED);
		init_pair(12, COLOR_MAGENTA, COLOR_BLUE);
		init_pair(13, COLOR_YELLOW, COLOR_GREEN);
		init_pair(14, COLOR_RED, COLOR_GREEN);
		eval { assume_default_colors($main::foreground, $main::background) } unless $main::is_win;
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
	$main::has_colors = has_colors();
	do_initscr();

	show_screen();
}

my $ceasing = 0;

# cease communications
sub cease
{
	my $sendz = shift;

	print "ceasing ($ceasing)\r\n";

	return if $ceasing;
	++$ceasing;

	$conn->disconnect if $conn;
	dbgclose();
	endwin();
	$decease->send;

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
	if ($main::has_colors) {
		foreach my $ref (@colors) {
			if ($_[0] =~ m{$$ref[0]}) {
				$top->attrset($$ref[1]);
				last;
			}
		}
	}
}

# measure the no of screen lines a line will take
sub measure
{
	my $line = shift;
	return 0 unless $line;

	my $l = length $line;
	my $lines = int ($l / $cols);
	$lines++ if $l / $cols > $lines;
	return $lines;
}

# display the top screen
sub show_screen
{
	if ($spos == @shistory - 1) {

		# if we really are scrolling thru at the end of the history
		my $line = $shistory[$spos];
		$top->addstr("\n") if $spos > 0;
		setattr($line);
		$top->addstr($line);
#		$top->addstr("\n");
		$top->attrset(COLOR_PAIR(0)) if $main::has_colors;
		$spos = @shistory;
		
	} else {
		
		# anywhere else
		my ($i, $l);
		my $p = $spos-1;
		for ($i = 0; $i < $pagel && $p >= 0; ) {
			$l = measure($shistory[$p]);
			$i += $l;
			$p-- if $i < $pagel;
		}
		$p = 0 if $p < 0;
		
		$top->move(0, 0);
		$top->attrset(COLOR_PAIR(0)) if $main::has_colors;
		$top->clrtobot();
		for ($i = 0; $i < $pagel && $p < @shistory; $p++) {
			my $line = $shistory[$p];
			my $lines = measure($line);
			last if $i + $lines > $pagel;
			$top->addstr("\n") if $i;
			setattr($line);
			$top->addstr($line);
			$top->attrset(COLOR_PAIR(0)) if $main::has_colors;
			$i += $lines;
		}
		$spos = $p;
		$spos = @shistory if $spos > @shistory;
	}
    my $shl = @shistory;
	my $size = $lines . 'x' . $cols . '-'; 
	my $add = "-$spos-$shl";
    my $time = ztime(time);
	my $str =  "-" . $time . '-' x ($cols - (length($size) + length($call) + length($add) + length($time) + 1));
	$scr->addstr($lines-4, 0, $str);
	
	$scr->addstr($size);
	$scr->attrset($mycallcolor) if $main::has_colors;
	$scr->addstr($call);
	$scr->attrset(COLOR_PAIR(0)) if $main::has_colors;
    $scr->addstr($add);
	$scr->refresh();
#	$top->refresh();
}

# add a line to the end of the top screen
sub addtotop
{
	while (@_) {
		my $inbuf = shift;
		if ($inbuf =~ s/\x07+$//) {
			beep();
		}
		if (length $inbuf >= $cols) {
			$Text::Wrap::Columns = $cols;
			push @shistory, wrap('',"\t", $inbuf);
		} else {
			push @shistory, $inbuf;
		}
		shift @shistory while @shistory > $maxshist;
	}
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
		my ($sort, $call, $line) = $msg =~ /^(\w)([^\|]+)\|(.*)$/;
		
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
				for ($i = $#khistory; $i >= 0; $i--) {
					if ($khistory[$i] =~ /^$inbuf/) {
						$inbuf = $khistory[$i];
						last;
					}
				}
				if ($i < 0) {
					beep();
					return;
				}
			}
			push @khistory, $inbuf if length $inbuf;
			shift @khistory if @khistory > $maxkhist;
			$khistpos = @khistory;
			$bot->move(0,0);
			$bot->clrtoeol();
			$bot->addstr(substr($inbuf, 0, $cols));

			# add it to the monitor window
			unless ($spos == @shistory) {
				$spos = @shistory;
				show_screen();
			};
			addtotop($inbuf);
		
			# send it to the cluster
			$conn->send_later("I$call|$inbuf");
			$inbuf = "";
			$pos = $lth = 0;
		} elsif ($r eq KEY_UP || $r eq "\020") {
			if ($khistpos > 0) {
				--$khistpos;
				$inbuf = $khistory[$khistpos];
				$pos = $lth = length $inbuf;
			} else {
				beep();
			}
		} elsif ($r eq KEY_DOWN || $r eq "\016") {
			if ($khistpos < @khistory - 1) {
				++$khistpos;
				$inbuf = $khistory[$khistpos];
				$pos = $lth = length $inbuf;
			} else {
				beep();
			}
		} elsif ($r eq KEY_PPAGE || $r eq "\032") {
			if ($spos > 0) {
				my ($i, $l);
				for ($i = 0; $i < $pagel-1 && $spos >= 0; ) {
					$l = measure($shistory[$spos]);
					$i += $l;
					$spos-- if $i <= $pagel;
				}
				$spos = 0 if $spos < 0;
				show_screen();
			} else {
				beep();
			}
		} elsif ($r eq KEY_NPAGE || $r eq "\026") {
			if ($spos < @shistory - 1) {
				my ($i, $l);
				for ($i = 0; $i <= $pagel && $spos <= @shistory; ) {
					$l = measure($shistory[$spos]);
					$i += $l;
					$spos++ if $i <= $pagel;
				}
				$spos = @shistory if $spos >= @shistory - 1;
				show_screen();
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
			if ($spos < @shistory) {
				$spos = @shistory;
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

sub idle_loop
{
	my $t;
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
#		mydbg("Got Resize");
#		do_resize();
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

#
# deal with args
#

$call = uc shift @ARGV if @ARGV;
$call = uc $main::myalias if !$call;
my ($scall, $ssid) = split /-/, $call;
$ssid = undef unless $ssid && $ssid =~ /^\d+$/;  
if ($ssid) {
	$ssid = 15 if $ssid > 15;
	$call = "$scall-$ssid";
}

if ($call eq $main::mycall) {
	print "You cannot connect as your cluster callsign ($main::mycall)\n";
	exit(0);
}

# create end condvar
$decease = AnyEvent->condvar;

dbginit();

$conn = IntMsg->connect("$main::clusteraddr", $main::clusterport, \&rec_socket);
if (! $conn) {
	if (-r "$main::root/data/offline") {
		open IN, "$main::root/data/offline" or die;
		while (<IN>) {
			print $_;
		}
		close IN;
	} else {
		print "Sorry, the cluster $main::mycall is currently off-line\n";
	}
	exit(0);
}


unless ($DB::VERSION) {
	$sigint = AnyEvent->signal(signal=>'INT', cb=> sub{$decease->send});
	$sigterm = AnyEvent->signal(signal=>'TERM', cb=> sub{$decease->send});
}

#$SIG{'HUP'} = \&sig_term;
my $sighup = AnyEvent->signal(signal=>'HUP', cb=> sub{$decease->send});
$conn->{sock}->on_eof(sub{$decease->send});
$conn->{sock}->on_error(sub{$decease->send});

# start up
do_resize();

#$SIG{__DIE__} = \&sig_term;
#my $sigdie = AnyEvent->signal(signal=>'__DIE__', cb=> sub{$decease->send});

$conn->send_later("A$call|$connsort width=$cols");
$conn->send_later("I$call|set/page $maxshist");
#$conn->send_later("I$call|set/nobeep");

#Msg->set_event_handler(\*STDIN, "read" => \&rec_stdin);

$Text::Wrap::Columns = $cols;

my $event_loop =  AnyEvent->timer(after => 0, interval => 0.010, cb => sub{idle_loop()});

$decease->recv;

cease(0);
