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
use vars qw(%work @msg $msgdir %valid);

%work = ();                # outstanding jobs
@msg = ();                 # messages we have
$msgdir = "$main::root/msg";              # directory contain the msgs

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
  read => '9,Times read',
  size => '0,Size',
  msgno => '0,Msgno',
);

# allocate a new object
# called fromnode, tonode, from, to, datetime, private?, subject, nolinesper  
sub alloc                  
{
  my $pkg = shift;
  my $self = bless {}, $pkg;
  $self->{msgno} = shift;
  $self->{to} = shift;
  $self->{from} = shift;
  $self->{t} = shift;
  $self->{private} = shift;
  $self->{subject} = shift;
  $self->{origin} = shift;
  $self->{read} = shift;
    
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
  my @f = split /[\^\~]/, $line;
  my ($pcno) = $f[0] =~ /^PC(\d\d)/;          # just get the number
  
  SWITCH: {
    if ($pcno == 28) {                        # incoming message
	  my $t = cltounix($f[5], $f[6]);
	  my $stream = next_transno($f[2]);
	  my $ref = DXMsg->alloc($stream, $f[3], $f[4], $t, $f[7], $f[8], $f[13], '0');
	  
	  # fill in various forwarding state variables
      $ref->{fromnode} = $f[2];
      $ref->{tonode} = $f[1];
	  $ref->{rrreq} = $f[11];
	  $ref->{linesreq} = $f[10];
	  $ref->{stream} = $stream;
	  $ref->{count} = 0;                      # no of lines between PC31s
	  dbg('msg', "new message from $f[4] to $f[3] '$f[8]' stream $stream\n");
      $work{"$f[1]$f[2]$stream"} = $ref;         # store in work
	  $self->send(DXProt::pc30($f[2], $f[1], $stream)); # send ack
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
		$ref->store($ref->{lines});                    # store it (whatever that may mean)
		$ref->workclean;
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
	  last SWITCH if $f[3] =~ /^\/(perl|cmd|local_cmd|src|lib|include|sys|msg)\//;    # prevent access to executables
	  
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
	  my $ref = DXMsg->alloc($stream, "$main::root/$f[3]", $self->call, time, !$f[4], $f[3], ' ', '0');
	  
	  # forwarding variables
      $ref->{fromnode} = $f[1];
      $ref->{tonode} = $f[2];
	  $ref->{linesreq} = $f[5];
	  $ref->{stream} = $stream;
	  $ref->{count} = 0;                      # no of lines between PC31s
	  $ref->{file} = 1;
      $work{"$f[1]$f[2]$stream"} = $ref;         # store in work
	  $self->send(DXProt::pc30($f[2], $f[1], $stream));  # send ack 
	  
	  last SWITCH;
	}
  }
}


# store a message away on disc or whatever
sub store
{
  my $ref = shift;
  my $lines = shift;
  
  # we only proceed if there are actually any lines in the file
  if (@{$lines} == 0) {
	return;
  }
  
  if ($ref->{file}) {   # a file
    dbg('msg', "To be stored in $ref->{to}\n");
  
    my $fh = new FileHandle "$ref->{to}", "w";
	if (defined $fh) {
	  my $line;
	  foreach $line (@{$lines}) {
		print $fh "$line\n";
	  }
	  $fh->close;
	  dbg('msg', "file $ref->{to} stored\n");
    } else {
      confess "can't open file $ref->{to} $!";  
    }
#	push @{$ref->{gotit}}, $ref->{fromnode} if $ref->{fromnode};
  } else {              # a normal message

    # get the next msg no - note that this has NOTHING to do with the stream number in PC protocol
	my $msgno = next_transno("Msgno");

    # attempt to open the message file
	my $fn = filename($msgno);

    dbg('msg', "To be stored in $fn\n");
  
    my $fh = new FileHandle "$fn", "w";
	if (defined $fh) {
      print $fh "=== $msgno^$ref->{to}^$ref->{from}^$ref->{t}^$ref->{private}^$ref->{subject}^$ref->{origin}^$ref->{read}\n";
	  print $fh "=== $ref->{fromnode}\n";
	  my $line;
	  foreach $line (@{$lines}) {
        $ref->{size} += (length $line) + 1;
		print $fh "$line\n";
	  }
	  $ref->{gotit} = [];
	  $ref->{msgno} = $msgno;
	  push @{$ref->{gotit}}, $ref->{fromnode} if $ref->{fromnode};
	  push @msg, $ref;           # add this message to the incore message list
	  $fh->close;
	  dbg('msg', "msg $msgno stored\n");
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
  
  # remove the file
  unlink filename($self->{msgno});
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
  $line = <$file>;       # first line
  chomp $line;
  $size -= length $line;
  if (! $line =~ /^===/o) {
    print "corrupt first line in $fn ($line)\n";
    return undef;
  }
  $line =~ s/^=== //o;
  @f = split /\^/, $line;
  $ref = DXMsg->alloc(@f);
  
  $line = <$file>;       # second line
  chomp $line;
  $size -= length $line;
  if (! $line =~ /^===/o) {
    print "corrupt second line in $fn ($line)\n";
    return undef;
  }
  $line =~ s/^=== //o;
  $ref->{gotit} = [];
  @f = split /\^/, $line;
  push @{$ref->{goit}}, @f;
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
  
  shift @out if $out[0] =~ /^=== \d+\^/;
  shift @out if $out[0] =~ /^=== \d+\^/;
  return @out;
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

# initialise the message 'system', read in all the message headers
sub init
{
  my $dir = new FileHandle;
  my @dir;
  my $ref;

  # read in the directory
  opendir($dir, $msgdir) or confess "can't open $msgdir $!";
  @dir = readdir($dir);
  closedir($dir);
  
  for (sort @dir) {
    next if /^\./o;
	next if ! /^m\d+/o;

    $ref = read_msg_header("$msgdir/$_");
	next if !$ref;
	
	# add the clusters that have this
	push @msg, $ref; 
	
  }
}

# return all the current messages
sub get_all
{
  return @msg;
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
