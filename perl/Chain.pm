package Chain;

use strict;
use Carp;

use vars qw($VERSION $BRANCH);
$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /\d+\.\d+\.(\d+)\.(\d+)/,(0,0));
$main::build += $VERSION;
$main::branch += $BRANCH;

use constant NEXT => 0;
use constant PREV => 1;
use constant OBJ => 2;

use vars qw($docheck);

$docheck = 0;
			
sub _check
{
	confess("chain broken $_[1]") unless ref $_[0] && $_[0]->isa('Chain') &&
		$_[0]->[PREV]->[NEXT] == $_[0] &&
			$_[0]->[NEXT]->[PREV] == $_[0];
	return 1;
}

# set internal checking
sub setcheck
{
	$docheck = shift;
}

# constructor			
sub new
{
	my $pkg = shift;
	my $name = ref $pkg || $pkg;

	my $self = [];
	push @$self, $self, $self, @_;
	return bless $self, $name;
}

# Insert before this point of the chain
sub ins
{
	my ($p, $ref) = @_;
	
	$docheck && _check($p);
	
	my $q = ref $ref && $ref->isa('Chain') ? $ref : Chain->new($ref);
	$q->[PREV] = $p->[PREV];
	$q->[NEXT] = $p;
	$p->[PREV]->[NEXT] = $q;
	$p->[PREV] = $q;
}

# Insert after this point of the chain
sub add  
{
	my ($p, $ref) = @_;
	
	$docheck && _check($p);
	
	$p->[NEXT]->ins($ref);
}

# Delete this item from the chain, returns the NEXT item in the chain
sub del
{
	my $p = shift;
	
	$docheck && _check($p);
	
	my $q = $p->[PREV]->[NEXT] = $p->[NEXT];
	$p->[NEXT]->[PREV] = $p->[PREV];
	$p->[NEXT] = $p->[PREV] = undef;
	return $q;
}

# Is this chain empty?
sub isempty
{
	my $p = shift;
	
	$docheck && _check($p);
	
	return $p->[NEXT] == $p;
}

# return next item or undef if end of chain
sub next
{
	my ($base, $p) = @_;
	
	$docheck && _check($base);
	
	return $base->[NEXT] == $base ? undef : $base->[NEXT] unless $p; 
	
	$docheck && _check($p);
	
	return $p->[NEXT] != $base ? $p->[NEXT] : undef; 
}

# return previous item or undef if end of chain
sub prev
{
	my ($base, $p) = @_;
	
	$docheck && _check($base);
	
	return $base->[PREV] == $base ? undef : $base->[PREV] unless $p; 
	
	$docheck && _check($p);
	
	return $p->[PREV] != $base ? $p->[PREV] : undef; 
}

# return (and optionally replace) the object in this chain item
sub obj
{
	my ($p, $ref) = @_;
	$p->[OBJ] = $ref if $ref;
	return $p->[OBJ];
}

# clear out the chain
sub flush
{
	my $base = shift;
	while (!$base->isempty) {
		$base->[NEXT]->del;
	}
}

# move this item after the 'base' item
sub rechain
{
	my ($base, $p) = @_;
	
	$docheck && _check($base, "base") && _check($p, "rechained ref");
	
	$p->del;
	$base->add($p);
}

# count the no of items in a chain
sub count
{
	my $base = shift;
	my $count;
	my $p;
	
	++$count while ($p = $base->next($p));
	return $count;
}

sub close
{
	my $base = shift;
	$base->flush;
	$base->[PREV] = $base->[NEXT] = undef;
}

1;
__END__
# Below is the stub of documentation for your module. You better edit it!

=head1 NAME

Chain - Double linked circular chain handler

=head1 SYNOPSIS

  use Chain;
  $base = new Chain [$obj];
  $p->ins($ref [,$obj]);
  $p->add($ref [,$obj]);
  $ref = $p->obj or $p->obj($ref);
  $q = $base->next($p);
  $q = $base->prev($p);
  $base->isempty;			
  $q = $p->del;
  $base->flush;
  $base->rechain($p);  			
  $base->count;

  Chain::setcheck(0);

=head1 DESCRIPTION

A module to handle those nasty jobs where a perl list simply will
not do what is required.

This module is a transliteration from a C routine I wrote in 1987, which
in turn was taken directly from the doubly linked list handling in ICL
George 3 originally written in GIN5 circa 1970. 

The type of list this module manipulates is circularly doubly linked
with a base.  This means that you can traverse the list backwards or
forwards from any point.  

The particular quality that makes this sort of list useful is that you
can insert and delete items anywhere in the list without having to
worry about end effects. 

The list has a I<base> but it doesn't have any real end!  The I<base> is
really just another (invisible) list member that you choose to
remember the position of and is the reference point that determines
what is an I<end>.

There is nothing special about a I<base>. You can choose another member 
of the list to be a I<base> whenever you like.

The difference between this module and a normal list is that it allows
one to create persistant arbitrary directed graphs reasonably
efficiently that are easy to traverse, insert and delete objects. You
will never need to use I<splice>, I<grep> or I<map> again (for this
sort of thing).

A particular use of B<Chain> is for connection maps that come and go
during the course of execution of your program.

An artificial example of this is:-

  use Chain;

  my $base = new Chain;
  $base->ins({call=>'GB7BAA', users => new Chain});
  $base->ins({call=>'GB7DJK', users => new Chain});
  $base->ins({call=>'GB7MRS', users => new Chain});

  # order is now GB7BAA, GB7DJK, GB7MRS
  
  my $p;
  while ($p = $base->next($p)) {
    my $obj = $p->obj;
    if ($obj->{call} eq 'GB7DJK') {
      my $ubase = $obj->{users};
      $ubase->ins( {call => 'G1TLH'} );
      $ubase->ins( {call => 'G7BRN'} );
    } elsif ($obj->{call} eq 'GB7MRS') {
      my $ubase = $obj->{users};
      $ubase->ins( {call => 'G4BAH'} );
      $ubase->ins( {call => 'G4PIQ'} );
    } elsif ($obj->{call} eq 'GB7BAA') {
      my $ubase = $obj->{users};
      $ubase->ins( {call => 'G8TIC'} );
      $ubase->ins( {call => 'M0VHF'} );
    }
  }

  # move the one on the end to the beginning (LRU on a stick :-).
  $base->rechain($base->prev);

  # order is now GB7MRS, GB7BAA, GB7DJK

  # this is exactly equivalent to :
  my $p = $base->prev;
  $p->del;
  $base->add($p);

  # order is now GB7DJK, GB7MRS, GB7BAA

  # disconnect (ie remove) GB7MRS
  for ($p = 0; $p = $base->next($p); ) {
    if ($p->obj->{call} eq 'GB7MRS') {
      $p->del;                     # remove this 'branch' from the tree
      $p->obj->{users}->flush;     # get rid of all its users
      last;
    }
  }
 
  
    
=head1 AUTHOR

Dirk Koopman <djk@tobit.co.uk>

=head1 SEE ALSO

ICL George 3 internals reference manual (a.k.a the source)

=cut
