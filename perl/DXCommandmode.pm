#!/usr/bin/perl
#
# This module impliments the user facing command mode for a dx cluster
#
# Copyright (c) 1998 Dirk Koopman G1TLH
#
# $Id$
# 

package DXCommandmode;

@ISA = qw(DXChannel);

use DXUtil;
use DXChannel;
use DXUser;
use DXVars;
use DXDebug;

use strict;
use vars qw( %Cache $last_dir_mtime @cmd);

$last_dir_mtime = 0;          # the last time one of the cmd dirs was modified
@cmd = undef;                 # a list of commands+path pairs (in alphabetical order)

# this is how a a connection starts, you get a hello message and the motd with
# possibly some other messages asking you to set various things up if you are
# new (or nearly new and slacking) user.

sub start
{ 
  my ($self, $line) = @_;
  my $user = $self->{user};
  my $call = $self->{call};
  my $name = $user->{name};

  $self->{name} = $name ? $name : $call;
  $self->msg('l2',$self->{name});
  $self->send_file($main::motd) if (-e $main::motd);
  $self->msg('pr', $call);
  $self->state('prompt');                  # a bit of room for further expansion, passwords etc
  $self->{priv} = $user->priv;
  $self->{priv} = 0 if $line =~ /^(ax|te)/;     # set the connection priv to 0 - can be upgraded later
  $self->{consort} = $line;                # save the connection type
}

#
# This is the normal command prompt driver
#
sub normal
{
  my $self = shift;
  my $user = $self->{user};
  my $call = $self->{call};
  my $cmdline = shift; 

  # strip out //
  $cmdline =~ s|//|/|og;
  
  # split the command line up into parts, the first part is the command
  my ($cmd, $args) = $cmdline =~ /^([\w\/]+)\s*(.*)/o;

  if ($cmd) {

    # first expand out the entry to a command
    $cmd = search($cmd);

    my @ans = $self->eval_file($main::localcmd, $cmd, $args);
	@ans = $self->eval_file($main::cmd, $cmd, $args) if !$ans[0];
	if ($ans[0]) {
      shift @ans;
	  $self->send(@ans) if @ans > 0;
	} else {
      shift @ans;
	  if (@ans > 0) {
	    $self->msg('e2', @ans);
	  } else {
        $self->msg('e1');
	  }
	}
  } else {
    $self->msg('e1');
  }
  
  # send a prompt only if we are in a prompt state
  $self->prompt() if $self->{state} =~ /^prompt/o;
}

#
# This is called from inside the main cluster processing loop and is used
# for despatching commands that are doing some long processing job
#
sub process
{

}

#
# finish up a user context
#
sub finish
{

}

#
# short cut to output a prompt
#

sub prompt
{
  my $self = shift;
  my $call = $self->{call};
  DXChannel::msg($self, 'pr', $call);
}

#
# search for the command in the cache of short->long form commands
#

sub search
{
  my $short_cmd = shift;
  return $short_cmd;    # just return it for now
}  

#
# the persistant execution of things from the command directories
#
#
# This allows perl programs to call functions dynamically
# 
# This has been nicked directly from the perlembed pages
#

#require Devel::Symdump;  

sub valid_package_name {
  my($string) = @_;
  $string =~ s/([^A-Za-z0-9\/])/sprintf("_%2x",unpack("C",$1))/eg;
  
  #second pass only for words starting with a digit
  $string =~ s|/(\d)|sprintf("/_%2x",unpack("C",$1))|eg;
	
  #Dress it up as a real package name
  $string =~ s|/|_|g;
  return "Emb_" . $string;
}

#borrowed from Safe.pm
sub delete_package {
  my $pkg = shift;
  my ($stem, $leaf);
	
  no strict 'refs';
  $pkg = "DXChannel::$pkg\::";    # expand to full symbol table name
  ($stem, $leaf) = $pkg =~ m/(.*::)(\w+::)$/;
	
  my $stem_symtab = *{$stem}{HASH};
	
  delete $stem_symtab->{$leaf};
}

sub eval_file {
  my $self = shift;
  my $path = shift;
  my $cmdname = shift;
  my $package = valid_package_name($cmdname);
  my $filename = "$path/$cmdname.pl";
  my $mtime = -M $filename;
  
  # return if we can't find it
  return (0, DXM::msg('e1')) if !defined $mtime;
  
  if(defined $Cache{$package}{mtime} && $Cache{$package}{mtime } <= $mtime) {
    #we have compiled this subroutine already,
	#it has not been updated on disk, nothing left to do
	#print STDERR "already compiled $package->handler\n";
	;
  } else {
	local *FH;
	if (!open FH, $filename) {
	  return (0, "Syserr: can't open '$filename' $!"); 
	};
	local($/) = undef;
	my $sub = <FH>;
	close FH;
		
    #wrap the code into a subroutine inside our unique package
	my $eval = qq{package DXChannel; sub $package { $sub; }};
	if (isdbg('eval')) {
	  my @list = split /\n/, $eval;
	  my $line;
	  foreach (@list) {
	    dbg('eval', $_, "\n");
	  }
	}
	#print "eval $eval\n";
	{
	  #hide our variables within this block
	  my($filename,$mtime,$package,$sub);
	  eval $eval;
	}
	if ($@) {
	  delete_package($package);
	  return (0, "Syserr: Eval err $@ on $package");
	}
		
	#cache it unless we're cleaning out each time
	$Cache{$package}{mtime} = $mtime;
  }
  
  my @r;
  my $c = qq{ \@r = \$self->$package(\@_); };
  dbg('eval', "cluster cmd = $c\n");
  eval  $c; ;
  if ($@) {
    delete_package($package);
	return (0, "Syserr: Eval err $@ on cached $package");
  }

  #take a look if you want
  #print Devel::Symdump->rnew($package)->as_string, $/;
  return @r;
}

1;
__END__
