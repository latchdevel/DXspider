#!/usr/bin/perl
#
# This module impliments the user facing command mode for a dx cluster
#
# Copyright (c) 1998 Dirk Koopman G1TLH
#
# $Id$
# 

package DXCommandmode;

use DXUtil;
use DXChannel;
use DXUser;
use DXM;
use DXVars;

$last_dir_mtime = 0;          # the last time one of the cmd dirs was modified
@cmd = undef;                 # a list of commands+path pairs (in alphabetical order)

# this is how a a connection starts, you get a hello message and the motd with
# possibly some other messages asking you to set various things up if you are
# new (or nearly new and slacking) user.

sub user_start
{ 
  my $self = shift;
  my $user = $self->{user};
  my $call = $self->{call};
  my $name = $self->{name};
  $name = $call if !defined $name;
  $self->{normal} = \&user_normal;    # rfu for now
  $self->{finish} = \&user_finish;
  $self->msg('l2',$name);
  $self->send_file($main::motd) if (-e $main::motd);
  $self->msg('pr', $call);
  $self->state('prompt');                  # a bit of room for further expansion, passwords etc
  $self->{priv} = 0;                  # set the connection priv to 0 - can be upgraded later
}

#
# This is the normal command prompt driver
#
sub user_normal
{
  my $self = shift;
  my $user = $self->{user};
  my $call = $self->{call};
  my $cmd = shift; 

  # read in the list of valid commands, note that the commands themselves are cached elsewhere
  scan_cmd_dirs if (!defined %cmd);
  
  # strip out any nasty characters like $@%&|. and double // etc.
  $cmd =~ s/[%\@\$&\\.`~]//og;
  $cmd =~ s|//|/|og;
  
  # split the command up into parts
  my @part = split /[\/\b]+/, $cmd;

  # the bye command - temporary probably
  if ($part[0] =~ /^b/io) {
    $self->user_finish();
	$self->state('bye');
	return;
  }

  # first expand out the entry to a command, note that I will accept 
  # anything in any case with any (reasonable) seperator
  $self->prompt();
}

#
# This is called from inside the main cluster processing loop and is used
# for despatching commands that are doing some long processing job
#
sub user_process
{

}

#
# finish up a user context
#
sub user_finish
{

}

#
# short cut to output a prompt
#

sub prompt
{
  my $self = shift;
  my $call = $self->{call};
  $self->msg('pr', $call);
}

#
# scan the command directories to see if things have changed
#
# If they have remake the command list
#
# There are two command directories a) the standard one and b) the local one
# The local one overides the standard one
#

sub scan_cmd_dirs
{
  my $self = shift;


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
use strict;
use vars '%Cache';

sub valid_package_name {
  my($string) = @_;
  $string =~ s/([^A-Za-z0-9\/])/sprintf("_%2x",unpack("C",$1))/eg;
  
  #second pass only for words starting with a digit
  $string =~ s|/(\d)|sprintf("/_%2x",unpack("C",$1))|eg;
	
  #Dress it up as a real package name
  $string =~ s|/|::|g;
  return "DXEmbed" . $string;
}

#borrowed from Safe.pm
sub delete_package {
  my $pkg = shift;
  my ($stem, $leaf);
	
  no strict 'refs';
  $pkg = "main::$pkg\::";    # expand to full symbol table name
  ($stem, $leaf) = $pkg =~ m/(.*::)(\w+::)$/;
	
  my $stem_symtab = *{$stem}{HASH};
	
  delete $stem_symtab->{$leaf};
}

sub eval_file {
  my($self, $path, $cmdname) = @_;
  my $package = valid_package_name($cmdname);
  my $filename = "$path/$cmdname";
  my $mtime = -M $filename;
  my @r;
  
  if(defined $Cache{$package}{mtime} && $Cache{$package}{mtime } <= $mtime) {
    #we have compiled this subroutine already,
	#it has not been updated on disk, nothing left to do
	#print STDERR "already compiled $package->handler\n";
	;
  } else {
	local *FH;
	open FH, $filename or die "open '$filename' $!";
	local($/) = undef;
	my $sub = <FH>;
	close FH;
		
    #wrap the code into a subroutine inside our unique package
	my $eval = qq{package $package; sub handler { $sub; }};
	{
	  #hide our variables within this block
	  my($filename,$mtime,$package,$sub);
	  eval $eval;
	}
	if ($@) {
	  $self->send("Eval err $@ on $package");
	  delete_package($package);
	  return undef;
	}
		
	#cache it unless we're cleaning out each time
	$Cache{$package}{mtime} = $mtime;
  }

  @r = eval {$package->handler;};
  if ($@) {
    $self->send("Eval err $@ on cached $package");
    delete_package($package);
	return undef;
  }

  #take a look if you want
  #print Devel::Symdump->rnew($package)->as_string, $/;
  return @r;
}

1;
__END__
