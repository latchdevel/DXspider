#!/usr/bin/perl
#
# This module impliments the message handling for a dx cluster
#
# Copyright (c) 1998 Dirk Koopman G1TLH
#
# $Id$
#
#
# Notes for implementors:-
#
# PC28 field 11 is the RR required flag
# PC28 field 12 is a VIA routing (ie it is a node call) 
#

package DXMsg;

use DXUtil;
use DXChannel;
use DXUser;
use DXM;
use DXProtVars;
use DXProtout;
use DXDebug;
use DXLog;
use IO::File;
use Fcntl;

use strict;

use vars qw($VERSION $BRANCH);
$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /\d+\.\d+\.(\d+)\.(\d+)/ ) || 0;
$main::build += $VERSION;
$main::branch += $BRANCH;

use vars qw(%work @msg $msgdir %valid %busy $maxage $last_clean
			@badmsg @swop $swopfn $badmsgfn $forwardfn @forward $timeout $waittime
		    $queueinterval $lastq $importfn $minchunk $maxchunk $bulltopriv);

%work = ();						# outstanding jobs
@msg = ();						# messages we have
%busy = ();						# station interlocks
$msgdir = "$main::root/msg";	# directory contain the msgs
$maxage = 30 * 86400;			# the maximum age that a message shall live for if not marked 
$last_clean = 0;				# last time we did a clean
@forward = ();                  # msg forward table
@badmsg = ();					# bad message table
@swop = ();						# swop table
$timeout = 30*60;               # forwarding timeout
$waittime = 30*60;              # time an aborted outgoing message waits before trying again
$queueinterval = 1*60;          # run the queue every 1 minute
$lastq = 0;

$minchunk = 4800;               # minimum chunk size for a split message
$maxchunk = 6000;               # maximum chunk size
$bulltopriv = 1;				# convert msgs with callsigns to private if they are bulls


$badmsgfn = "$msgdir/badmsg.pl";    # list of TO address we wont store
$forwardfn = "$msgdir/forward.pl";  # the forwarding table
$swopfn = "$msgdir/swop.pl";        # the swopping table
$importfn = "$msgdir/import";       # import directory


%valid = (
		  fromnode => '5,From Node',
		  tonode => '5,To Node',
		  to => '0,To',
		  from => '0,From',
		  t => '0,Msg Time,cldatetime',
		  private => '5,Private',
		  subject => '0,Subject',
		  linesreq => '0,Lines per Gob',
		  rrreq => '5,Read Confirm',
		  origin => '0,Origin',
		  lines => '5,Data',
		  stream => '9,Stream No',
		  count => '5,Gob Linecnt',
		  file => '5,File?,yesno',
		  gotit => '5,Got it Nodes,parray',
		  lines => '5,Lines,parray',
		  'read' => '5,Times read',
		  size => '0,Size',
		  msgno => '0,Msgno',
		  keep => '0,Keep this?,yesno',
		  lastt => '5,Last processed,cldatetime',
		  waitt => '5,Wait until,cldatetime',
		 );

# allocate a new object
# called fromnode, tonode, from, to, datetime, private?, subject, nolinesper  
sub alloc                  
{
	my $pkg = shift;
	my $self = bless {}, $pkg;
	$self->{msgno} = shift;
	my $to = shift;
	#  $to =~ s/-\d+$//o;
	$self->{to} = ($to eq $main::mycall) ? $main::myalias : $to;
	my $from = shift;
	$from =~ s/-\d+$//o;
	$self->{from} = uc $from;
	$self->{t} = shift;
	$self->{private} = shift;
	$self->{subject} = shift;
	$self->{origin} = shift;
	$self->{'read'} = shift;
	$self->{rrreq} = shift;
	$self->{gotit} = [];
#	$self->{lastt} = $main::systime;
	$self->{lines} = [];
	$self->{private} = 1 if $bulltopriv && DXUser->get_current($self->{to});
    
	return $self;
}

sub workclean
{
	my $ref = shift;
	delete $ref->{lines};
	delete $ref->{linesreq};
	delete $ref->{tonode};
	delete $ref->{fromnode};
	delete $ref->{stream};
	delete $ref->{file};
	delete $ref->{count};
	delete $ref->{lastt} if exists $ref->{lastt};
	delete $ref->{waitt} if exists $ref->{waitt};
}

sub process
{
	my ($self, $line) = @_;

	# this is periodic processing
	if (!$self || !$line) {

		if ($main::systime >= $lastq + $queueinterval) {

			# queue some message if the interval timer has gone off
			queue_msg(0);

			# import any messages in the import directory
			import_msgs();
			
			$lastq = $main::systime;
		}

		# clean the message queue
		clean_old() if $main::systime - $last_clean > 3600 ;
		return;
	}

	my @f = split /\^/, $line;
	my ($pcno) = $f[0] =~ /^PC(\d\d)/; # just get the number

 SWITCH: {
		if ($pcno == 28) {		# incoming message

			# sort out various extant protocol errors that occur
			my ($fromnode, $origin);
			if ($self->is_arcluster && $f[13] eq $self->call) {
				$fromnode = $f[13];
				$origin = $f[2];
			} else {
				$fromnode = $f[2];
			    $origin = $f[13];
			}
			$origin = $self->call unless $origin && $origin gt ' ';

			# first look for any messages in the busy queue 
			# and cancel them this should both resolve timed out incoming messages
			# and crossing of message between nodes, incoming messages have priority

			if (exists $busy{$fromnode}) {
				my $ref = $busy{$fromnode};
				my $tonode = $ref->{tonode} || "unknown";
				dbg("Busy, stopping msgno: $ref->{msgno} $fromnode->$tonode") if isdbg('msg');
				$ref->stop_msg($self->call);
			}

			my $t = cltounix($f[5], $f[6]);
			my $stream = next_transno($fromnode);
			my $ref = DXMsg->alloc($stream, uc $f[3], $f[4], $t, $f[7], $f[8], $origin, '0', $f[11]);
			
			# fill in various forwarding state variables
			$ref->{fromnode} = $fromnode;
			$ref->{tonode} = $f[1];
			$ref->{rrreq} = $f[11];
			$ref->{linesreq} = $f[10];
			$ref->{stream} = $stream;
			$ref->{count} = 0;	# no of lines between PC31s
			dbg("new message from $f[4] to $f[3] '$f[8]' stream $fromnode/$stream\n") if isdbg('msg');
			Log('msg', "Incoming message $f[4] to $f[3] '$f[8]'" );
			$work{"$fromnode$stream"} = $ref; # store in work
			$busy{$fromnode} = $ref; # set interlock
			$self->send(DXProt::pc30($fromnode, $f[1], $stream)); # send ack
			$ref->{lastt} = $main::systime;

			# look to see whether this is a non private message sent to a known callsign
			my $uref = DXUser->get_current($ref->{to});
			if (is_callsign($ref->{to}) && !$ref->{private} && $uref && $uref->homenode) {
				$ref->{private} = 1;
				dbg("set bull to $ref->{to} to private") if isdbg('msg');
			}
			last SWITCH;
		}
		
		if ($pcno == 29) {		# incoming text
			my $ref = $work{"$f[2]$f[3]"};
			if ($ref) {
				$f[4] =~ s/\%5E/^/g;
				push @{$ref->{lines}}, $f[4];
				$ref->{count}++;
				if ($ref->{count} >= $ref->{linesreq}) {
					$self->send(DXProt::pc31($f[2], $f[1], $f[3]));
					dbg("stream $f[3]: $ref->{count} lines received\n") if isdbg('msg');
					$ref->{count} = 0;
				}
				$ref->{lastt} = $main::systime;
			} else {
				dbg("PC29 from unknown stream $f[3] from $f[2]") if isdbg('msg');
				$self->send(DXProt::pc42($f[2], $f[1], $f[3]));	# unknown stream
			}
			last SWITCH;
		}
		
		if ($pcno == 30) {		# this is a incoming subject ack
			my $ref = $work{$f[2]};	# note no stream at this stage
			if ($ref) {
				delete $work{$f[2]};
				$ref->{stream} = $f[3];
				$ref->{count} = 0;
				$ref->{linesreq} = 5;
				$work{"$f[2]$f[3]"} = $ref;	# new ref
				dbg("incoming subject ack stream $f[3]\n") if isdbg('msg');
				$busy{$f[2]} = $ref; # interlock
				push @{$ref->{lines}}, ($ref->read_msg_body);
				$ref->send_tranche($self);
				$ref->{lastt} = $main::systime;
			} else {
				dbg("PC30 from unknown stream $f[3] from $f[2]") if isdbg('msg');
				$self->send(DXProt::pc42($f[2], $f[1], $f[3]));	# unknown stream
			} 
			last SWITCH;
		}
		
		if ($pcno == 31) {		# acknowledge a tranche of lines
			my $ref = $work{"$f[2]$f[3]"};
			if ($ref) {
				dbg("tranche ack stream $f[3]\n") if isdbg('msg');
				$ref->send_tranche($self);
				$ref->{lastt} = $main::systime;
			} else {
				dbg("PC31 from unknown stream $f[3] from $f[2]") if isdbg('msg');
				$self->send(DXProt::pc42($f[2], $f[1], $f[3]));	# unknown stream
			} 
			last SWITCH;
		}
		
		if ($pcno == 32) {		# incoming EOM
			dbg("stream $f[3]: EOM received\n") if isdbg('msg');
			my $ref = $work{"$f[2]$f[3]"};
			if ($ref) {
				$self->send(DXProt::pc33($f[2], $f[1], $f[3]));	# acknowledge it
				
				# get the next msg no - note that this has NOTHING to do with the stream number in PC protocol
				# store the file or message
				# remove extraneous rubbish from the hash
				# remove it from the work in progress vector
				# stuff it on the msg queue
				if ($ref->{lines}) {
					if ($ref->{file}) {
						$ref->store($ref->{lines});
					} else {

						# does an identical message already exist?
						my $m;
						for $m (@msg) {
							if ($ref->{subject} eq $m->{subject} && $ref->{t} == $m->{t} && $ref->{from} eq $m->{from} && $ref->{to} eq $m->{to}) {
								$ref->stop_msg($self->call);
								my $msgno = $m->{msgno};
								dbg("duplicate message from $ref->{from} -> $ref->{to} to $msgno") if isdbg('msg');
								Log('msg', "duplicate message from $ref->{from} -> $ref->{to} to $msgno");
								return;
							}
						}

						# swop addresses
						$ref->swop_it($self->call);
						
						# look for 'bad' to addresses 
						if ($ref->dump_it($self->call)) {
							$ref->stop_msg($self->call);
							dbg("'Bad' message $ref->{to}") if isdbg('msg');
							Log('msg', "'Bad' message $ref->{to}");
							return;
						}

						$ref->{msgno} = next_transno("Msgno");
						push @{$ref->{gotit}}, $f[2]; # mark this up as being received
						$ref->store($ref->{lines});
						add_dir($ref);
						my $dxchan = DXChannel->get($ref->{to});
						$dxchan->send($dxchan->msg('m9')) if $dxchan && $dxchan->is_user;
						Log('msg', "Message $ref->{msgno} from $ref->{from} received from $f[2] for $ref->{to}");
					}
				}
				$ref->stop_msg($self->call);
			} else {
				dbg("PC32 from unknown stream $f[3] from $f[2]") if isdbg('msg');
				$self->send(DXProt::pc42($f[2], $f[1], $f[3]));	# unknown stream
			}
			# queue_msg(0);
			last SWITCH;
		}
		
		if ($pcno == 33) {		# acknowledge the end of message
			my $ref = $work{"$f[2]$f[3]"};
			if ($ref) {
				if ($ref->{private}) { # remove it if it private and gone off site#
					Log('msg', "Message $ref->{msgno} from $ref->{from} sent to $f[2] and deleted");
					$ref->del_msg;
				} else {
					Log('msg', "Message $ref->{msgno} from $ref->{from} sent to $f[2]");
					push @{$ref->{gotit}}, $f[2]; # mark this up as being received
					$ref->store($ref->{lines});	# re- store the file
				}
				$ref->stop_msg($self->call);
			} else {
				dbg("PC33 from unknown stream $f[3] from $f[2]") if isdbg('msg');
				$self->send(DXProt::pc42($f[2], $f[1], $f[3]));	# unknown stream
			} 

			# send next one if present
			queue_msg(0);
			last SWITCH;
		}
		
		if ($pcno == 40) {		# this is a file request
			$f[3] =~ s/\\/\//og; # change the slashes
			$f[3] =~ s/\.//og;	# remove dots
			$f[3] =~ s/^\///o;   # remove the leading /
			$f[3] = lc $f[3];	# to lower case;
			dbg("incoming file $f[3]\n") if isdbg('msg');
			$f[3] = 'packclus/' . $f[3] unless $f[3] =~ /^packclus\//o;
			
			# create any directories
			my @part = split /\//, $f[3];
			my $part;
			my $fn = "$main::root";
			pop @part;			# remove last part
			foreach $part (@part) {
				$fn .= "/$part";
				next if -e $fn;
				last SWITCH if !mkdir $fn, 0777;
				dbg("created directory $fn\n") if isdbg('msg');
			}
			my $stream = next_transno($f[2]);
			my $ref = DXMsg->alloc($stream, "$main::root/$f[3]", $self->call, time, !$f[4], $f[3], ' ', '0', '0');
			
			# forwarding variables
			$ref->{fromnode} = $f[1];
			$ref->{tonode} = $f[2];
			$ref->{linesreq} = $f[5];
			$ref->{stream} = $stream;
			$ref->{count} = 0;	# no of lines between PC31s
			$ref->{file} = 1;
			$ref->{lastt} = $main::systime;
			$work{"$f[2]$stream"} = $ref; # store in work
			$self->send(DXProt::pc30($f[2], $f[1], $stream)); # send ack 
			
			last SWITCH;
		}
		
		if ($pcno == 42) {		# abort transfer
			dbg("stream $f[3]: abort received\n") if isdbg('msg');
			my $ref = $work{"$f[2]$f[3]"};
			if ($ref) {
				$ref->stop_msg($self->call);
				$ref = undef;
			}
			last SWITCH;
		}

		if ($pcno == 49) {      # global delete on subject
			for (@msg) {
				if ($_->{from} eq $f[1] && $_->{subject} eq $f[2]) {
					$_->del_msg();
					Log('msg', "Message $_->{msgno} from $_->{from} ($_->{subject}) fully deleted");
					DXChannel::broadcast_nodes($line, $self);
				}
			}
		}
	}
}


# store a message away on disc or whatever
#
# NOTE the second arg is a REFERENCE not a list
sub store
{
	my $ref = shift;
	my $lines = shift;

	if ($ref->{file}) {			# a file
		dbg("To be stored in $ref->{to}\n") if isdbg('msg');
		
		my $fh = new IO::File "$ref->{to}", "w";
		if (defined $fh) {
			my $line;
			foreach $line (@{$lines}) {
				print $fh "$line\n";
			}
			$fh->close;
			dbg("file $ref->{to} stored\n") if isdbg('msg');
			Log('msg', "file $ref->{to} from $ref->{from} stored" );
		} else {
			confess "can't open file $ref->{to} $!";  
		}
	} else {					# a normal message

		# attempt to open the message file
		my $fn = filename($ref->{msgno});
		
		dbg("To be stored in $fn\n") if isdbg('msg');
		
		# now save the file, overwriting what's there, YES I KNOW OK! (I will change it if it's a problem)
		my $fh = new IO::File "$fn", "w";
		if (defined $fh) {
			my $rr = $ref->{rrreq} ? '1' : '0';
			my $priv = $ref->{private} ? '1': '0';
			print $fh "=== $ref->{msgno}^$ref->{to}^$ref->{from}^$ref->{t}^$priv^$ref->{subject}^$ref->{origin}^$ref->{'read'}^$rr\n";
			print $fh "=== ", join('^', @{$ref->{gotit}}), "\n";
			my $line;
			$ref->{size} = 0;
			foreach $line (@{$lines}) {
				$ref->{size} += (length $line) + 1;
				print $fh "$line\n";
			}
			$fh->close;
			dbg("msg $ref->{msgno} stored\n") if isdbg('msg');
			Log('msg', "msg $ref->{msgno} from $ref->{from} to $ref->{to} stored" );
		} else {
			confess "can't open msg file $fn $!";  
		}
	}
}

# delete a message
sub del_msg
{
	my $self = shift;
	
	# remove it from the active message list
	dbg("\@msg = " . scalar @msg . " before delete") if isdbg('msg');
	@msg = grep { $_ != $self } @msg;
	
	# remove the file
	unlink filename($self->{msgno});
	dbg("deleting $self->{msgno}\n") if isdbg('msg');
	dbg("\@msg = " . scalar @msg . " after delete") if isdbg('msg');
}

# clean out old messages from the message queue
sub clean_old
{
	my $ref;
	
	# mark old messages for deletion
	dbg("\@msg = " . scalar @msg . " before delete") if isdbg('msg');
	foreach $ref (@msg) {
		if (ref($ref) && !$ref->{keep} && $ref->{t} < $main::systime - $maxage) {
			$ref->{deleteme} = 1;
			unlink filename($ref->{msgno});
			dbg("deleting old $ref->{msgno}\n") if isdbg('msg');
		}
	}
	
	# remove them all from the active message list
	@msg = grep { !$_->{deleteme} } @msg;
	dbg("\@msg = " . scalar @msg . " after delete") if isdbg('msg');
	$last_clean = $main::systime;
}

# read in a message header
sub read_msg_header
{ 
	my $fn = shift;
	my $file;
	my $line;
	my $ref;
	my @f;
	my $size;
	
	$file = new IO::File "$fn";
	if (!$file) {
	    dbg("Error reading $fn $!");
	    Log('err', "Error reading $fn $!");
		return undef;
	}
	$size = -s $fn;
	$line = <$file>;			# first line
	if ($size == 0 || !$line) {
	    dbg("Empty $fn $!");
	    Log('err', "Empty $fn $!");
		return undef;
	}
	chomp $line;
	$size -= length $line;
	if (! $line =~ /^===/o) {
		dbg("corrupt first line in $fn ($line)");
		Log('err', "corrupt first line in $fn ($line)");
		return undef;
	}
	$line =~ s/^=== //o;
	@f = split /\^/, $line;
	$ref = DXMsg->alloc(@f);
	
	$line = <$file>;			# second line
	chomp $line;
	$size -= length $line;
	if (! $line =~ /^===/o) {
	    dbg("corrupt second line in $fn ($line)");
	    Log('err', "corrupt second line in $fn ($line)");
		return undef;
	}
	$line =~ s/^=== //o;
	$ref->{gotit} = [];
	@f = split /\^/, $line;
	push @{$ref->{gotit}}, @f;
	$ref->{size} = $size;
	
	close($file);
	
	return $ref;
}

# read in a message header
sub read_msg_body
{
	my $self = shift;
	my $msgno = $self->{msgno};
	my $file;
	my $line;
	my $fn = filename($msgno);
	my @out;
	
	$file = new IO::File;
	if (!open($file, $fn)) {
		dbg("Error reading $fn $!");
		Log('err' ,"Error reading $fn $!");
		return undef;
	}
	@out = map {chomp; $_} <$file>;
	close($file);
	
	shift @out if $out[0] =~ /^=== /;
	shift @out if $out[0] =~ /^=== /;
	return @out;
}

# send a tranche of lines to the other end
sub send_tranche
{
	my ($self, $dxchan) = @_;
	my @out;
	my $to = $self->{tonode};
	my $from = $self->{fromnode};
	my $stream = $self->{stream};
	my $lines = $self->{lines};
	my ($c, $i);
	
	for ($i = 0, $c = $self->{count}; $i < $self->{linesreq} && $c < @$lines; $i++, $c++) {
		push @out, DXProt::pc29($to, $from, $stream, $lines->[$c]);
    }
    $self->{count} = $c;

    push @out, DXProt::pc32($to, $from, $stream) if $i < $self->{linesreq};
	$dxchan->send(@out);
}

	
# find a message to send out and start the ball rolling
sub queue_msg
{
	my $sort = shift;
	my $ref;
	my $clref;
	
	# bat down the message list looking for one that needs to go off site and whose
	# nearest node is not busy.

	dbg("queue msg ($sort)\n") if isdbg('msg');
	my @nodelist = DXChannel::get_all_nodes;
	foreach $ref (@msg) {

		# ignore 'delayed' messages until their waiting time has expired
		if (exists $ref->{waitt}) {
			next if $ref->{waitt} > $main::systime;
			delete $ref->{waitt};
		} 

		# any time outs?
		if (exists $ref->{lastt} && $main::systime >= $ref->{lastt} + $timeout) {
			my $node = $ref->{tonode};
			dbg("Timeout, stopping msgno: $ref->{msgno} -> $node") if isdbg('msg');
			Log('msg', "Timeout, stopping msgno: $ref->{msgno} -> $node");
			$ref->stop_msg($node);
			
			# delay any outgoing messages that fail
			$ref->{waitt} = $main::systime + $waittime + rand(120) if $node ne $main::mycall;
			delete $ref->{lastt};
			next;
		}

		# firstly, is it private and unread? if so can I find the recipient
		# in my cluster node list offsite?

		# deal with routed private messages
		my $dxchan;
		if ($ref->{private}) {
			next if $ref->{'read'};           # if it is read, it is stuck here
			$clref = Route::get($ref->{to});
#			unless ($clref) {             # otherwise look for a homenode
#				my $uref = DXUser->get_current($ref->{to});
#				my $hnode =  $uref->homenode if $uref;
#				$clref = Route::Node::get($hnode) if $hnode;
#			}
			if ($clref) {
				$dxchan = $clref->dxchan;
				if ($dxchan) {
					if ($dxchan->is_node) {
						next if $clref->call eq $main::mycall;  # i.e. it lives here
						$ref->start_msg($dxchan) if !get_busy($dxchan->call)  && $dxchan->state eq 'normal';
					}
				} else {
					dbg("Route: No dxchan for $ref->{to} " . ref($clref) ) if isdbg('msg');
				}
			}
		} else {
			
			# otherwise we are dealing with a bulletin or forwarded private message
			# compare the gotit list with
			# the nodelist up above, if there are sites that haven't got it yet
			# then start sending it - what happens when we get loops is anyone's
			# guess, use (to, from, time, subject) tuple?
			foreach $dxchan (@nodelist) {
				my $call = $dxchan->call;
				next unless $call;
				next if $call eq $main::mycall;
				next if ref $ref->{gotit} && grep $_ eq $call, @{$ref->{gotit}};
				next unless $ref->forward_it($call);           # check the forwarding file
				
				# if we are here we have a node that doesn't have this message
				if (!get_busy($call)  && $dxchan->state eq 'normal') {
					$ref->start_msg($dxchan);
					last;
				}
			}
		}

		# if all the available nodes are busy then stop
		last if @nodelist == scalar grep { get_busy($_->call) } @nodelist;
	}
}

# is there a message for me?
sub for_me
{
	my $call = uc shift;
	my $ref;
	
	foreach $ref (@msg) {
		# is it for me, private and unread? 
		if ($ref->{to} eq $call && $ref->{private}) {
			return 1 if !$ref->{'read'};
		}
	}
	return 0;
}

# start the message off on its travels with a PC28
sub start_msg
{
	my ($self, $dxchan) = @_;
	
	dbg("start msg $self->{msgno}\n") if isdbg('msg');
	$self->{linesreq} = 10;
	$self->{count} = 0;
	$self->{tonode} = $dxchan->call;
	$self->{fromnode} = $main::mycall;
	$busy{$self->{tonode}} = $self;
	$work{$self->{tonode}} = $self;
	$self->{lastt} = $main::systime;
	my ($fromnode, $origin);
	if ($dxchan->is_arcluster) {
		$fromnode = $self->{origin};
		$origin = $self->{fromnode};
	} else {
		$fromnode = $self->{fromnode};
		$origin = $self->{origin};
	}
	$dxchan->send(DXProt::pc28($self->{tonode}, $fromnode, $self->{to}, $self->{from}, $self->{t}, $self->{private}, $self->{subject}, $origin, $self->{rrreq}));
}

# get the ref of a busy node
sub get_busy
{
	my $call = shift;
	return $busy{$call};
}

# get the busy queue
sub get_all_busy
{
	return values %busy;
}

# get the forwarding queue
sub get_fwq
{
	return values %work;
}

# stop a message from continuing, clean it out, unlock interlocks etc
sub stop_msg
{
	my $self = shift;
	my $node = shift;
	my $stream = $self->{stream} if exists $self->{stream};
	
	
	dbg("stop msg $self->{msgno} -> node $node\n") if isdbg('msg');
	delete $work{$node};
	delete $work{"$node$stream"} if $stream;
	$self->workclean;
	delete $busy{$node};
}

# get a new transaction number from the file specified
sub next_transno
{
	my $name = shift;
	$name =~ s/\W//og;			# remove non-word characters
	my $fn = "$msgdir/$name";
	my $msgno;
	
	my $fh = new IO::File;
	if (sysopen($fh, $fn, O_RDWR|O_CREAT, 0666)) {
		$fh->autoflush(1);
		$msgno = $fh->getline || '0';
		chomp $msgno;
		$msgno++;
		seek $fh, 0, 0;
		$fh->print("$msgno\n");
		dbg("msgno $msgno allocated for $name\n") if isdbg('msg');
		$fh->close;
	} else {
		confess "can't open $fn $!";
	}
	return $msgno;
}

# initialise the message 'system', read in all the message headers
sub init
{
	my $dir = new IO::File;
	my @dir;
	my $ref;
		
	# load various control files
	dbg("load badmsg: " . (load_badmsg() or "Ok"));
	dbg("load forward: " . (load_forward() or "Ok"));
	dbg("load swop: " . (load_swop() or "Ok"));

	# read in the directory
	opendir($dir, $msgdir) or confess "can't open $msgdir $!";
	@dir = readdir($dir);
	closedir($dir);

	@msg = ();
	for (sort @dir) {
		next unless /^m\d\d\d\d\d\d$/;
		
		$ref = read_msg_header("$msgdir/$_");
		unless ($ref) {
			dbg("Deleting $_");
			Log('err', "Deleting $_");
			unlink "$msgdir/$_";
			next;
		}
		
		# delete any messages to 'badmsg.pl' places
		if ($ref->dump_it('')) {
			dbg("'Bad' TO address $ref->{to}") if isdbg('msg');
			Log('msg', "'Bad' TO address $ref->{to}");
			$ref->del_msg;
			next;
		}

		# add the message to the available queue
		add_dir($ref); 
	}
}

# add the message to the directory listing
sub add_dir
{
	my $ref = shift;
	confess "tried to add a non-ref to the msg directory" if !ref $ref;
	push @msg, $ref;
}

# return all the current messages
sub get_all
{
	return @msg;
}

# get a particular message
sub get
{
	my $msgno = shift;
	for (@msg) {
		return $_ if $_->{msgno} == $msgno;
		last if $_->{msgno} > $msgno;
	}
	return undef;
}

# return the official filename for a message no
sub filename
{
	return sprintf "$msgdir/m%06d", shift;
}

#
# return a list of valid elements 
# 

sub fields
{
	return keys(%valid);
}

#
# return a prompt for a field
#

sub field_prompt
{ 
	my ($self, $ele) = @_;
	return $valid{$ele};
}

#
# send a message state machine
sub do_send_stuff
{
	my $self = shift;
	my $line = shift;
	my @out;
	
	if ($self->state eq 'send1') {
		#  $DB::single = 1;
		confess "local var gone missing" if !ref $self->{loc};
		my $loc = $self->{loc};
		$loc->{subject} = $line;
		$loc->{lines} = [];
		$self->state('sendbody');
		#push @out, $self->msg('sendbody');
		push @out, $self->msg('m8');
	} elsif ($self->state eq 'sendbody') {
		confess "local var gone missing" if !ref $self->{loc};
		my $loc = $self->{loc};
		if ($line eq "\032" || $line eq '%1A' || uc $line eq "/EX") {
			my $to;
			
			foreach $to (@{$loc->{to}}) {
				my $ref;
				my $systime = $main::systime;
				my $mycall = $main::mycall;
				$ref = DXMsg->alloc(DXMsg::next_transno('Msgno'),
									uc $to,
									exists $loc->{from} ? $loc->{from} : $self->call, 
									$systime,
									$loc->{private}, 
									$loc->{subject}, 
									exists $loc->{origin} ? $loc->{origin} : $mycall,
									'0',
									$loc->{rrreq});
				$ref->swop_it($self->call);
				$ref->store($loc->{lines});
				$ref->add_dir();
				push @out, $self->msg('m11', $ref->{msgno}, $to);
				#push @out, "msgno $ref->{msgno} sent to $to";
				my $dxchan = DXChannel->get(uc $to);
				if ($dxchan) {
					if ($dxchan->is_user()) {
						$dxchan->send($dxchan->msg('m9'));
					}
				}
			}

			delete $loc->{lines};
			delete $loc->{to};
			delete $self->{loc};
			$self->func(undef);
			
			$self->state('prompt');
		} elsif ($line eq "\031" || uc $line eq "/ABORT" || uc $line eq "/QUIT") {
			#push @out, $self->msg('sendabort');
			push @out, $self->msg('m10');
			delete $loc->{lines};
			delete $loc->{to};
			delete $self->{loc};
			$self->func(undef);
			$self->state('prompt');
		} else {
			
			# i.e. it ain't and end or abort, therefore store the line
			push @{$loc->{lines}}, length($line) > 0 ? $line : " ";
		}
	}
	return (1, @out);
}

# return the standard directory line for this ref 
sub dir
{
	my $ref = shift;
	return sprintf "%6d%s%s%5d %8.8s %8.8s %-6.6s %5.5s %-30.30s", 
		$ref->msgno, $ref->read ? '-' : ' ', $ref->private ? 'p' : ' ', $ref->size,
			$ref->to, $ref->from, cldate($ref->t), ztime($ref->t), $ref->subject;
}

# load the forward table
sub load_forward
{
	my @out;
	my $s = readfilestr($forwardfn);
	if ($s) {
		eval $s;
		push @out, $@ if $@;
	}
	return @out;
}

# load the bad message table
sub load_badmsg
{
	my @out;
	my $s = readfilestr($badmsgfn);
	if ($s) {
		eval $s;
		push @out, $@ if $@;
	}
	return @out;
}

# load the swop message table
sub load_swop
{
	my @out;
	my $s = readfilestr($swopfn);
	if ($s) {
		eval $s;
		push @out, $@ if $@;
	}
	return @out;
}

#
# forward that message or not according to the forwarding table
# returns 1 for forward, 0 - to ignore
#

sub forward_it
{
	my $ref = shift;
	my $call = shift;
	my $i;
	
	for ($i = 0; $i < @forward; $i += 5) {
		my ($sort, $field, $pattern, $action, $bbs) = @forward[$i..($i+4)]; 
		my $tested;
		
		# are we interested?
		next if $ref->{private} && $sort ne 'P';
		next if !$ref->{private} && $sort ne 'B';
		
		# select field
		$tested = $ref->{to} if $field eq 'T';
		$tested = $ref->{from} if $field eq 'F';
		$tested = $ref->{origin} if $field eq 'O';
		$tested = $ref->{subject} if $field eq 'S';

		if (!$pattern || $tested =~ m{$pattern}i) {
			return 0 if $action eq 'I';
			return 1 if !$bbs || grep $_ eq $call, @{$bbs};
		}
	}
	return 0;
}

sub dump_it
{
	my $ref = shift;
	my $call = shift;
	my $i;
	
	for ($i = 0; $i < @badmsg; $i += 3) {
		my ($sort, $field, $pattern) = @badmsg[$i..($i+2)]; 
		my $tested;
		
		# are we interested?
		next if $ref->{private} && $sort ne 'P';
		next if !$ref->{private} && $sort ne 'B';
		
		# select field
		$tested = $ref->{to} if $field eq 'T';
		$tested = $ref->{from} if $field eq 'F';
		$tested = $ref->{origin} if $field eq 'O';
		$tested = $ref->{subject} if $field eq 'S';
		$tested = $call if $field eq 'I';

		if (!$pattern || $tested =~ m{$pattern}i) {
			return 1;
		}
	}
	return 0;
}

sub swop_it
{
	my $ref = shift;
	my $call = shift;
	my $i;
	my $count = 0;
	
	for ($i = 0; $i < @swop; $i += 5) {
		my ($sort, $field, $pattern, $tfield, $topattern) = @swop[$i..($i+4)]; 
		my $tested;
		my $swop;
		my $old;
		
		# are we interested?
		next if $ref->{private} && $sort ne 'P';
		next if !$ref->{private} && $sort ne 'B';
		
		# select field
		$tested = $ref->{to} if $field eq 'T';
		$tested = $ref->{from} if $field eq 'F';
		$tested = $ref->{origin} if $field eq 'O';
		$tested = $ref->{subject} if $field eq 'S';

		# select swop field
		$old = $swop = $ref->{to} if $tfield eq 'T';
		$old = $swop = $ref->{from} if $tfield eq 'F';
		$old = $swop = $ref->{origin} if $tfield eq 'O';
		$old = $swop = $ref->{subject} if $tfield eq 'S';

		if ($tested =~ m{$pattern}i) {
			if ($tested eq $swop) {
				$swop =~ s{$pattern}{$topattern}i;
			} else {
				$swop = $topattern;
			}
			Log('msg', "Msg $ref->{msgno}: $tfield $old -> $swop");
			Log('dbg', "Msg $ref->{msgno}: $tfield $old -> $swop");
			$ref->{to} = $swop if $tfield eq 'T';
			$ref->{from} = $swop if $tfield eq 'F';
			$ref->{origin} = $swop if $tfield eq 'O';
			$ref->{subject} = $swop if $tfield eq 'S';
			++$count;
		}
	}
	return $count;
}

# import any msgs in the import directory
# the messages are in BBS format (but may have cluster extentions
# so SB UK < GB7TLH is legal
sub import_msgs
{
	# are there any to do in this directory?
	return unless -d $importfn;
	unless (opendir(DIR, $importfn)) {
		dbg("can\'t open $importfn $!") if isdbg('msg');
		Log('msg', "can\'t open $importfn $!");
		return;
	} 

	my @names = readdir(DIR);
	closedir(DIR);
	my $name;
	foreach $name (@names) {
		next if $name =~ /^\./;
		my $splitit = $name =~ /^split/;
		my $fn = "$importfn/$name";
		next unless -f $fn;
		unless (open(MSG, $fn)) {
	 		dbg("can\'t open import file $fn $!") if isdbg('msg');
			Log('msg', "can\'t open import file $fn $!");
			unlink($fn);
			next;
		}
		my @msg = map { chomp; $_ } <MSG>;
		close(MSG);
		unlink($fn);
		my @out = import_one($main::me, \@msg, $splitit);
		Log('msg', @out);
	}
}

# import one message as a list in bbs (as extended) mode
# takes a reference to an array containing the whole message
sub import_one
{
	my $dxchan = shift;
	my $ref = shift;
	my $splitit = shift;
	my $private = '1';
	my $rr = '0';
	my $notincalls = 1;
	my $from = $dxchan->call;
	my $origin = $main::mycall;
	my @to;
	my @out;
				
	# first line;
	my $line = shift @$ref;
	my @f = split /\s+/, $line;
 	unless (@f && $f[0] =~ /^(:?S|SP|SB|SEND)$/ ) {
		my $m = "invalid first line in import '$line'";
		dbg($m) if isdbg('msg');
		return (1, $m);
	}
	while (@f) {
		my $f = uc shift @f;
		next if $f eq 'SEND';

		# private / noprivate / rr
		if ($notincalls && ($f eq 'B' || $f eq 'SB' || $f =~ /^NOP/oi)) {
			$private = '0';
		} elsif ($notincalls && ($f eq 'P' || $f eq 'SP' || $f =~ /^PRI/oi)) {
			;
		} elsif ($notincalls && ($f eq 'RR')) {
			$rr = '1';
		} elsif ($f eq '@' && @f) {       # this is bbs syntax, for origin
			$origin = uc shift @f;
		} elsif ($f eq '<' && @f) {     # this is bbs syntax  for from call
			$from = uc shift @f;
		} elsif ($f =~ /^\$/) {     # this is bbs syntax  for a bid
			next;
		} elsif ($f =~ /^<\S+/) {     # this is bbs syntax  for from call
			($from) = $f =~ /^<(\S+)$/;
		} elsif ($f =~ /^\@\S+/) {     # this is bbs syntax for origin
			($origin) = $f =~ /^\@(\S+)$/;
		} else {

			# callsign ?
			$notincalls = 0;

			# is this callsign a distro?
			my $fn = "$msgdir/distro/$f.pl";
			if (-e $fn) {
				my $fh = new IO::File $fn;
				if ($fh) {
					local $/ = undef;
					my $s = <$fh>;
					$fh->close;
					my @call;
					@call = eval $s;
					return (1, "Error in Distro $f.pl:", $@) if $@;
					if (@call > 0) {
						push @f, @call;
						next;
					}
				}
			}
			
			if (grep $_ eq $f, @DXMsg::badmsg) {
				push @out, $dxchan->msg('m3', $f);
			} else {
	 			push @to, $f;
			}
		}
	}
	
	# subject is the next line
	my $subject = shift @$ref;
	
	# strip off trailing lines 
	pop @$ref while (@$ref && $$ref[-1] =~ /^\s*$/);
	
	# strip off /EX or /ABORT
	return ("aborted") if @$ref && $$ref[-1] =~ m{^/ABORT$}i; 
	pop @$ref if (@$ref && $$ref[-1] =~ m{^/EX$}i);									 

	# sort out any splitting that needs to be done
	my @chunk;
	if ($splitit) {
		my $lth = 0;
		my $lines = [];
		for (@$ref) {
			if ($lth >= $maxchunk || ($lth > $minchunk && /^\s*$/)) {
				push @chunk, $lines;
				$lines = [];
				$lth = 0;
			} 
			push @$lines, $_;
			$lth += length; 
		}
		push @chunk, $lines if @$lines;
	} else {
		push @chunk, $ref;
	}
				  
    # write all the messages away
	my $i;
	for ( $i = 0;  $i < @chunk; $i++) {
		my $chunk = $chunk[$i];
		my $ch_subject;
		if (@chunk > 1) {
			my $num = " [" . ($i+1) . "/" . scalar @chunk . "]";
			$ch_subject = substr($subject, 0, 27 - length $num) .  $num;
		} else {
			$ch_subject = $subject;
		}
		my $to;
		foreach $to (@to) {
			my $systime = $main::systime;
			my $mycall = $main::mycall;
			my $mref = DXMsg->alloc(DXMsg::next_transno('Msgno'),
									$to,
									$from, 
									$systime,
									$private, 
									$ch_subject, 
									$origin,
									'0',
									$rr);
			$mref->swop_it($main::mycall);
			$mref->store($chunk);
			$mref->add_dir();
			push @out, $dxchan->msg('m11', $mref->{msgno}, $to);
			#push @out, "msgno $ref->{msgno} sent to $to";
			my $todxchan = DXChannel->get(uc $to);
			if ($todxchan) {
				if ($todxchan->is_user()) {
					$todxchan->send($todxchan->msg('m9'));
				}
			}
		}
	}
	return @out;
}

no strict;
sub AUTOLOAD
{
	my $self = shift;
	my $name = $AUTOLOAD;
	return if $name =~ /::DESTROY$/;
	$name =~ s/.*:://o;
	
	confess "Non-existant field '$AUTOLOAD'" if !$valid{$name};
	# this clever line of code creates a subroutine which takes over from autoload
	# from OO Perl - Conway
	*{$AUTOLOAD} = sub {@_ > 1 ? $_[0]->{$name} = $_[1] : $_[0]->{$name}} ;
	@_ ? $self->{$name} = shift : $self->{$name} ;
}

1;

__END__
