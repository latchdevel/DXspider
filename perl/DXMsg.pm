#!/usr/bin/perl
#
# This module impliments the message handling for a dx cluster
#
# Copyright (c) 1998 Dirk Koopman G1TLH
#
# $Id$
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
use FileHandle;
use Carp;

use strict;
use vars qw($stream %work @msg $msgdir $msgnofn);

%work = ();                # outstanding jobs
@msg = ();                 # messages we have
$msgdir = "$main::data/msg";              # directory contain the msgs

# allocate a new object
# called fromnode, tonode, from, to, datetime, private?, subject, nolinesper  
sub alloc                  
{
  my $pkg = shift;
  my $self = bless {}, $pkg;
  $self->{fromnode} = shift;
  $self->{tonode} = shift;
  $self->{to} = shift;
  $self->{from} = shift;
  $self->{t} = shift;
  $self->{private} = shift;
  $self->{subject} = shift;
  $self->{linesreq} = shift;    # this the number of lines to send or receive between PC31s
  $self->{rrreq} = shift;       # a read receipt is required
  $self->{origin} = shift;
  $self->{stream} = shift;
  $self->{lines} = [];
  
  return $self;
}

sub workclean
{
  my $ref = shift;
  delete $ref->{lines};
  delete $ref->{linesreq};
  delete $ref->{tonode};
  delete $ref->{stream};
}

sub process
{
  my ($self, $line) = @_;
  my @f = split /[\^\~]/, $line;
  my ($pcno) = $f[0] =~ /^PC(\d\d)/;          # just get the number
  
  SWITCH: {
    if ($pcno == 28) {                        # incoming message
	  my $t = cltounix($f[5], $f[6]);
	  my $stream = next_transno($f[2]);
	  my $ref = DXMsg->alloc($f[1], $f[2], $f[3], $f[4], $t, $f[7], $f[8], $f[10], $f[11], $f[13], $stream);
	  dbg('msg', "new message from $f[4] to $f[3] '$f[8]' stream $stream\n");
      $work{"$f[1]$f[2]$stream"} = $ref;         # store in work
	  $self->send(DXProt::pc30($f[2], $f[1], $stream)); 
	  $ref->{count} = 0;                      # no of lines between PC31s
	  last SWITCH;
	}
	
    if ($pcno == 29) {                        # incoming text
	  my $ref = $work{"$f[1]$f[2]$f[3]"};
	  if ($ref) {
	    push @{$ref->{lines}}, $f[4];
		$ref->{count}++;
		if ($ref->{count} >= $ref->{linesreq}) {
		  $self->send(DXProt::pc31($f[2], $f[1], $f[3]));
		  dbg('msg', "stream $f[3]: $ref->{linereq} lines received\n");
		  $ref->{count} = 0;
		}
	  }
	  last SWITCH;
	}
	
    if ($pcno == 30) {
	  last SWITCH;
	}
	
    if ($pcno == 31) {
	  last SWITCH;
	}
	
    if ($pcno == 32) {                         # incoming EOM
	  dbg('msg', "stream $f[3]: EOM received\n");
	  my $ref = $work{"$f[1]$f[2]$f[3]"};
	  if ($ref) {
	    $self->send(DXProt::pc33($f[2], $f[1], $f[3]));# acknowledge it
		$ref->store();                         # store it (whatever that may mean)
		delete $work{"$f[1]$f[2]$f[3]"};       # remove the reference from the work vector
	  }
	  last SWITCH;
	}
	
    if ($pcno == 33) {
	  last SWITCH;
	}
	
	if ($pcno == 40) {                         # this is a file request
	  $f[3] =~ s/\\/\//og;                     # change the slashes
	  $f[3] =~ s/\.//og;                       # remove dots
	  $f[3] = lc $f[3];                        # to lower case;
	  dbg('msg', "incoming file $f[3]\n");
	  last SWITCH if $f[3] =~ /^\/(perl|cmd|local_cmd|src|lib|include|sys|data\/msg)\//;    # prevent access to executables
	  
	  # create any directories
	  my @part = split /\//, $f[3];
	  my $part;
	  my $fn = "$main::root";
	  pop @part;         # remove last part
	  foreach $part (@part) {
	    $fn .= "/$part";
		next if -e $fn;
	    last SWITCH if !mkdir $fn, 0777;
        dbg('msg', "created directory $fn\n");
	  }
	  my $stream = next_transno($f[2]);
	  my $ref = DXMsg->alloc($f[1], $f[2], "$main::root/$f[3]", undef, time, !$f[4], undef, $f[5], 0, ' ', $stream);
	  $ref->{file} = 1;
      $work{"$f[1]$f[2]$stream"} = $ref;         # store in work
	  $self->send(DXProt::pc30($f[2], $f[1], $stream)); 
	  $ref->{count} = 0;                      # no of lines between PC31s
	  
	  last SWITCH;
	}
  }
}


# store a message away on disc or whatever
sub store
{
  my $ref = shift;
  
  # we only proceed if there are actually any lines in the file
  if (@{$ref->{lines}} == 0) {
    delete $ref->{lines};
	return;
  }
  
  if ($ref->{file}) {   # a file
    dbg('msg', "To be stored in $ref->{to}\n");
  
    my $fh = new FileHandle "$ref->{to}", "w";
	if (defined $fh) {
	  my $line;
	  foreach $line (@{$ref->{lines}}) {
		print $fh "$line\n";
	  }
	  $fh->close;
	  dbg('msg', "file $ref->{to} stored\n");
    } else {
      confess "can't open file $ref->{to} $!";  
    }
  } else {              # a normal message

    # get the next msg no - note that this has NOTHING to do with the stream number in PC protocol
	my $msgno = next_transno("msgno");

    # attempt to open the message file
	my $fn = sprintf "$msgdir/m%06d", $msgno;

    dbg('msg', "To be stored in $fn\n");
  
    my $fh = new FileHandle "$fn", "w";
	if (defined $fh) {
      print $fh "=== $ref->{to}^$ref->{from}^$ref->{private}^$ref->{subject}^$ref->{origin}\n";
	  print $fh "=== $ref->{fromnode}\n";
	  my $line;
	  foreach $line (@{$ref->{lines}}) {
        $ref->{size} += length $line + 1;
		print $fh "$line\n";
	  }
	  $ref->workclean();
	  push @msg, $ref;           # add this message to the incore message list
	  $fh->close;
	  dbg('msg', "msg $msgno stored\n");
    } else {
      confess "can't open msg file $fn $!";  
    }
  }
}

# get a new transaction number from the file specified
sub next_transno
{
  my $name = shift;
  $name =~ s/\W//og;      # remove non-word characters
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

# initialise the message 'system'
sub init
{

}

1;

__END__
