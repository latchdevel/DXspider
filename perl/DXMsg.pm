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

@ISA = qw(DXProt DXChannel);

use DXUtil;
use DXChannel;
use DXUser;
use DXM;
use DXCluster;
use DXProtVars;
use DXProtout;
use DXDebug;
use DXLog;
use FileHandle;
use Carp;

use strict;
use vars qw(%work @msg $msgdir %valid %busy $maxage $last_clean
			@badmsg $badmsgfn $forwardfn @forward);

%work = ();						# outstanding jobs
@msg = ();						# messages we have
%busy = ();						# station interlocks
$msgdir = "$main::root/msg";	# directory contain the msgs
$maxage = 30 * 86400;			# the maximum age that a message shall live for if not marked 
$last_clean = 0;				# last time we did a clean
@forward = ();                  # msg forward table

$badmsgfn = "$msgdir/badmsg.pl";  # list of TO address we wont store
$forwardfn = "$msgdir/forward.pl";  # the forwarding table

%valid = (
		  fromnode => '9,From Node',
		  tonode => '9,To Node',
		  to => '0,To',
		  from => '0,From',
		  t => '0,Msg Time,cldatetime',
		  private => '9,Private',
		  subject => '0,Subject',
		  linesreq => '0,Lines per Gob',
		  rrreq => '9,Read Confirm',
		  origin => '0,Origin',
		  lines => '5,Data',
		  stream => '9,Stream No',
		  count => '9,Gob Linecnt',
		  file => '9,File?,yesno',
		  gotit => '9,Got it Nodes,parray',
		  lines => '9,Lines,parray',
		  'read' => '9,Times read',
		  size => '0,Size',
		  msgno => '0,Msgno',
		  keep => '0,Keep this?,yesno',
		 );

sub DESTROY
{
	my $self = shift;
	undef $self->{lines};
	undef $self->{gotit};
}

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
	delete $ref->{lines};
	delete $ref->{file};
	delete $ref->{count};
}

sub process
{
	my ($self, $line) = @_;
	my @f = split /\^/, $line;
	my ($pcno) = $f[0] =~ /^PC(\d\d)/; # just get the number
	
 SWITCH: {
		if ($pcno == 28) {		# incoming message
			my $t = cltounix($f[5], $f[6]);
			my $stream = next_transno($f[2]);
			my $ref = DXMsg->alloc($stream, uc $f[3], $f[4], $t, $f[7], $f[8], $f[13], '0', $f[11]);
			
			# fill in various forwarding state variables
			$ref->{fromnode} = $f[2];
			$ref->{tonode} = $f[1];
			$ref->{rrreq} = $f[11];
			$ref->{linesreq} = $f[10];
			$ref->{stream} = $stream;
			$ref->{count} = 0;	# no of lines between PC31s
			dbg('msg', "new message from $f[4] to $f[3] '$f[8]' stream $stream\n");
			$work{"$f[2]$stream"} = $ref; # store in work
			$busy{$f[2]} = $ref; # set interlock
			$self->send(DXProt::pc30($f[2], $f[1], $stream)); # send ack
			last SWITCH;
		}
		
		if ($pcno == 29) {		# incoming text
			my $ref = $work{"$f[2]$f[3]"};
			if ($ref) {
				push @{$ref->{lines}}, $f[4];
				$ref->{count}++;
				if ($ref->{count} >= $ref->{linesreq}) {
					$self->send(DXProt::pc31($f[2], $f[1], $f[3]));
					dbg('msg', "stream $f[3]: $ref->{count} lines received\n");
					$ref->{count} = 0;
				}
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
				dbg('msg', "incoming subject ack stream $f[3]\n");
				$busy{$f[2]} = $ref; # interlock
				$ref->{lines} = [];
				push @{$ref->{lines}}, ($ref->read_msg_body);
				$ref->send_tranche($self);
			} else {
				$self->send(DXProt::pc42($f[2], $f[1], $f[3]));	# unknown stream
			} 
			last SWITCH;
		}
		
		if ($pcno == 31) {		# acknowledge a tranche of lines
			my $ref = $work{"$f[2]$f[3]"};
			if ($ref) {
				dbg('msg', "tranche ack stream $f[3]\n");
				$ref->send_tranche($self);
			} else {
				$self->send(DXProt::pc42($f[2], $f[1], $f[3]));	# unknown stream
			} 
			last SWITCH;
		}
		
		if ($pcno == 32) {		# incoming EOM
			dbg('msg', "stream $f[3]: EOM received\n");
			my $ref = $work{"$f[2]$f[3]"};
			if ($ref) {
				$self->send(DXProt::pc33($f[2], $f[1], $f[3]));	# acknowledge it
				
				# get the next msg no - note that this has NOTHING to do with the stream number in PC protocol
				# store the file or message
				# remove extraneous rubbish from the hash
				# remove it from the work in progress vector
				# stuff it on the msg queue
				if ($ref->{lines} && @{$ref->{lines}} > 0) { # ignore messages with 0 lines
					if ($ref->{file}) {
						$ref->store($ref->{lines});
					} else {

						# does an identical message already exist?
						my $m;
						for $m (@msg) {
							if ($ref->{subject} eq $m->{subject} && $ref->{t} == $m->{t} && $ref->{from} eq $m->{from}) {
								$ref->stop_msg($self);
								my $msgno = $m->{msgno};
								dbg('msg', "duplicate message to $msgno\n");
								Log('msg', "duplicate message to $msgno");
								return;
							}
						}
							
						# look for 'bad' to addresses 
						if (grep $ref->{to} eq $_, @badmsg) {
							$ref->stop_msg($self);
							dbg('msg', "'Bad' TO address $ref->{to}");
							Log('msg', "'Bad' TO address $ref->{to}");
							return;
						}

						$ref->{msgno} = next_transno("Msgno");
						push @{$ref->{gotit}}, $f[2]; # mark this up as being received
						$ref->store($ref->{lines});
						add_dir($ref);
						my $dxchan = DXChannel->get($ref->{to});
						$dxchan->send($dxchan->msg('msgnew')) if $dxchan;
						Log('msg', "Message $ref->{msgno} from $ref->{from} received from $f[2] for $ref->{to}");
					}
				}
				$ref->stop_msg($self);
				queue_msg(0);
			} else {
				$self->send(DXProt::pc42($f[2], $f[1], $f[3]));	# unknown stream
			}
			queue_msg(0);
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
				$ref->stop_msg($self);
			} else {
				$self->send(DXProt::pc42($f[2], $f[1], $f[3]));	# unknown stream
			} 
			queue_msg(0);
			last SWITCH;
		}
		
		if ($pcno == 40) {		# this is a file request
			$f[3] =~ s/\\/\//og; # change the slashes
			$f[3] =~ s/\.//og;	# remove dots
			$f[3] =~ s/^\///o;   # remove the leading /
			$f[3] = lc $f[3];	# to lower case;
			dbg('msg', "incoming file $f[3]\n");
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
				dbg('msg', "created directory $fn\n");
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
			$work{"$f[2]$stream"} = $ref; # store in work
			$self->send(DXProt::pc30($f[2], $f[1], $stream)); # send ack 
			
			last SWITCH;
		}
		
		if ($pcno == 42) {		# abort transfer
			dbg('msg', "stream $f[3]: abort received\n");
			my $ref = $work{"$f[2]$f[3]"};
			if ($ref) {
				$ref->stop_msg($self);
				$ref = undef;
			}
			
			last SWITCH;
		}

		if ($pcno == 49) {      # global delete on subject
			for (@msg) {
				if ($_->{subject} eq $f[2]) {
					$_->del_msg();
					Log('msg', "Message $_->{msgno} fully deleted by $f[1]");
				}
			}
		}
	}
	
	clean_old() if $main::systime - $last_clean > 3600 ; # clean the message queue
}


# store a message away on disc or whatever
#
# NOTE the second arg is a REFERENCE not a list
sub store
{
	my $ref = shift;
	my $lines = shift;
	
	# we only proceed if there are actually any lines in the file
	if (!$lines || @{$lines} == 0) {
		return;
	}
	
	if ($ref->{file}) {			# a file
		dbg('msg', "To be stored in $ref->{to}\n");
		
		my $fh = new FileHandle "$ref->{to}", "w";
		if (defined $fh) {
			my $line;
			foreach $line (@{$lines}) {
				print $fh "$line\n";
			}
			$fh->close;
			dbg('msg', "file $ref->{to} stored\n");
			Log('msg', "file $ref->{to} from $ref->{from} stored" );
		} else {
			confess "can't open file $ref->{to} $!";  
		}
	} else {					# a normal message

		# attempt to open the message file
		my $fn = filename($ref->{msgno});
		
		dbg('msg', "To be stored in $fn\n");
		
		# now save the file, overwriting what's there, YES I KNOW OK! (I will change it if it's a problem)
		my $fh = new FileHandle "$fn", "w";
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
			dbg('msg', "msg $ref->{msgno} stored\n");
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
	@msg = map { $_ != $self ? $_ : () } @msg;
	
	# belt and braces (one day I will ask someone if this is REALLY necessary)
	delete $self->{gotit};
	delete $self->{list};
	
	# remove the file
	unlink filename($self->{msgno});
	dbg('msg', "deleting $self->{msgno}\n");
}

# clean out old messages from the message queue
sub clean_old
{
	my $ref;
	
	# mark old messages for deletion
	foreach $ref (@msg) {
		if (!$ref->{keep} && $ref->{t} < $main::systime - $maxage) {
			$ref->{deleteme} = 1;
			delete $ref->{gotit};
			delete $ref->{list};
			unlink filename($ref->{msgno});
			dbg('msg', "deleting old $ref->{msgno}\n");
		}
	}
	
	# remove them all from the active message list
	@msg = map { $_->{deleteme} ? () : $_ } @msg;
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
	
	$file = new FileHandle;
	if (!open($file, $fn)) {
		print "Error reading $fn $!\n";
		return undef;
	}
	$size = -s $fn;
	$line = <$file>;			# first line
	chomp $line;
	$size -= length $line;
	if (! $line =~ /^===/o) {
		print "corrupt first line in $fn ($line)\n";
		return undef;
	}
	$line =~ s/^=== //o;
	@f = split /\^/, $line;
	$ref = DXMsg->alloc(@f);
	
	$line = <$file>;			# second line
	chomp $line;
	$size -= length $line;
	if (! $line =~ /^===/o) {
		print "corrupt second line in $fn ($line)\n";
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
	
	$file = new FileHandle;
	if (!open($file, $fn)) {
		print "Error reading $fn $!\n";
		return undef;
	}
	chomp (@out = <$file>);
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
	my $call = shift;
	my $ref;
	my $clref;
	my $dxchan;
	my @nodelist = DXProt::get_all_ak1a();
	
	# bat down the message list looking for one that needs to go off site and whose
	# nearest node is not busy.

	dbg('msg', "queue msg ($sort)\n");
	foreach $ref (@msg) {
		# firstly, is it private and unread? if so can I find the recipient
		# in my cluster node list offsite?
		if ($ref->{private}) {
			if ($ref->{'read'} == 0) {
				$clref = DXCluster->get_exact($ref->{to});
				unless ($clref) {             # otherwise look for a homenode
					my $uref = DXUser->get($ref->{to});
					my $hnode =  $uref->homenode if $uref;
					$clref = DXCluster->get_exact($hnode) if $hnode;
				}
				if ($clref && !grep { $clref->{dxchan} == $_ } DXCommandmode::get_all) {
					$dxchan = $clref->{dxchan};
					$ref->start_msg($dxchan) if $dxchan && $clref && !get_busy($dxchan->call) && $dxchan->state eq 'normal';
				}
			}
		} elsif (!$sort) {
			# otherwise we are dealing with a bulletin, compare the gotit list with
			# the nodelist up above, if there are sites that haven't got it yet
			# then start sending it - what happens when we get loops is anyone's
			# guess, use (to, from, time, subject) tuple?
			my $noderef;
			foreach $noderef (@nodelist) {
				next if $noderef->call eq $main::mycall;
				next if grep { $_ eq $noderef->call } @{$ref->{gotit}};
				next unless $ref->forward_it($noderef->call);           # check the forwarding file
				# next if $noderef->isolate;               # maybe add code for stuff originated here?
				# next if DXUser->get( ${$ref->{gotit}}[0] )->isolate;  # is the origin isolated?
				
				# if we are here we have a node that doesn't have this message
				$ref->start_msg($noderef) if !get_busy($noderef->call)  && $noderef->state eq 'normal';
				last;
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
	
	dbg('msg', "start msg $self->{msgno}\n");
	$self->{linesreq} = 5;
	$self->{count} = 0;
	$self->{tonode} = $dxchan->call;
	$self->{fromnode} = $main::mycall;
	$busy{$dxchan->call} = $self;
	$work{"$self->{tonode}"} = $self;
	$dxchan->send(DXProt::pc28($self->{tonode}, $self->{fromnode}, $self->{to}, $self->{from}, $self->{t}, $self->{private}, $self->{subject}, $self->{origin}, $self->{rrreq}));
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
	my ($self, $dxchan) = @_;
	my $node = $dxchan->call;
	
	dbg('msg', "stop msg $self->{msgno} stream $self->{stream}\n");
	delete $work{$node};
	delete $work{"$node$self->{stream}"};
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
	
	my $fh = new FileHandle;
	if (sysopen($fh, $fn, O_RDWR|O_CREAT, 0666)) {
		$fh->autoflush(1);
		$msgno = $fh->getline;
		chomp $msgno;
		$msgno++;
		seek $fh, 0, 0;
		$fh->print("$msgno\n");
		dbg('msg', "msgno $msgno allocated for $name\n");
		$fh->close;
	} else {
		confess "can't open $fn $!";
	}
	return $msgno;
}

# initialise the message 'system', read in all the message headers
sub init
{
	my $dir = new FileHandle;
	my @dir;
	my $ref;

	# load various control files
	my @in = load_badmsg();
	print "@in\n" if @in;
	@in = load_forward();
	print "@in\n" if @in;

	# read in the directory
	opendir($dir, $msgdir) or confess "can't open $msgdir $!";
	@dir = readdir($dir);
	closedir($dir);

	@msg = ();
	for (sort @dir) {
		next unless /^m\d+$/o;
		
		$ref = read_msg_header("$msgdir/$_");
		next unless $ref;
		
		# delete any messages to 'badmsg.pl' places
		if (grep $ref->{to} eq $_, @badmsg) {
			dbg('msg', "'Bad' TO address $ref->{to}");
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
		push @out, "Enter Message /EX (^Z) to send or /ABORT (^Y) to exit";
	} elsif ($self->state eq 'sendbody') {
		confess "local var gone missing" if !ref $self->{loc};
		my $loc = $self->{loc};
		if ($line eq "\032" || uc $line eq "/EX") {
			my $to;
			
			if (@{$loc->{lines}} > 0) {
				foreach $to (@{$loc->{to}}) {
					my $ref;
					my $systime = $main::systime;
					my $mycall = $main::mycall;
					$ref = DXMsg->alloc(DXMsg::next_transno('Msgno'),
										uc $to,
										$self->call, 
										$systime,
										$loc->{private}, 
										$loc->{subject}, 
										$mycall,
										'0',
										$loc->{rrreq});
					$ref->store($loc->{lines});
					$ref->add_dir();
					#push @out, $self->msg('sendsent', $to);
					push @out, "msgno $ref->{msgno} sent to $to";
					my $dxchan = DXChannel->get(uc $to);
					if ($dxchan) {
						if ($dxchan->is_user()) {
							$dxchan->send("New mail has arrived for you");
						}
					}
				}
			}
			delete $loc->{lines};
			delete $loc->{to};
			delete $self->{loc};
			$self->func(undef);
			DXMsg::queue_msg(0);
			$self->state('prompt');
		} elsif ($line eq "\031" || uc $line eq "/ABORT" || uc $line eq "/QUIT") {
			#push @out, $self->msg('sendabort');
			push @out, "aborted";
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
	do "$forwardfn" if -e "$forwardfn";
	push @out, $@ if $@;
	return @out;
}

# load the bad message table
sub load_badmsg
{
	my @out;
	do "$badmsgfn" if -e "$badmsgfn";
	push @out, $@ if $@;
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
		last if $ref->{private} && $sort ne 'P';
		last if !$ref->{private} && $sort ne 'B';
		
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

no strict;
sub AUTOLOAD
{
	my $self = shift;
	my $name = $AUTOLOAD;
	return if $name =~ /::DESTROY$/;
	$name =~ s/.*:://o;
	
	confess "Non-existant field '$AUTOLOAD'" if !$valid{$name};
	@_ ? $self->{$name} = shift : $self->{$name} ;
}

1;

__END__
