#
# This module impliments the new protocal mode for a dx cluster
#
# Copyright (c) 2001 Dirk Koopman G1TLH
#
# $Id$
# 

package QXProt;

@ISA = qw(DXChannel DXProt);

use DXUtil;
use DXChannel;
use DXUser;
use DXM;
use DXLog;
use Spot;
use DXDebug;
use Filter;
use DXDb;
use AnnTalk;
use Geomag;
use WCY;
use Time::HiRes qw(gettimeofday tv_interval);
use BadWords;
use DXHash;
use Route;
use Route::Node;
use Script;
use DXProt;
use Verify;
use Thingy;

use strict;

use vars qw($VERSION $BRANCH);
$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /\d+\.\d+\.(\d+)\.(\d+)/,(0,0));
$main::build += $VERSION;
$main::branch += $BRANCH;

sub init
{
	my $user = DXUser->get($main::mycall);
	$DXProt::myprot_version += ($main::version - 1 + 0.52)*100;
	$main::me = QXProt->new($main::mycall, 0, $user); 
	$main::me->{here} = 1;
	$main::me->{state} = "indifferent";
	$main::me->{sort} = 'S';    # S for spider
	$main::me->{priv} = 9;
	$main::me->{metric} = 0;
	$main::me->{pingave} = 0;
	$main::me->{registered} = 1;
	$main::me->{version} = $main::version;
	$main::me->{build} = $main::build;
		
#	$Route::Node::me->adddxchan($main::me);
}

sub start
{
	my $self = shift;
	$self->SUPER::start(@_);
}

sub sendinit
{
	my $self = shift;
	
	$self->node_update;
}

sub normal
{
	if ($_[1] =~ /^PC\d\d\^/) {
		DXProt::normal(@_);
		return;
	}

	# Although this is called the 'QX' Protocol, this is historical
	# I am simply using this module to save a bit of time.
	# 
	
	return unless my ($tonode, $fromnode, $class, $msgid, $hoptime, $rest) = 
		$_[1] =~ /^([^;]+;){5,5}\|(.*)$/;

	my $self = shift;
	
	# add this interface's hop time to the one passed
	my $newhoptime = $self->{pingave} >= 999 ? 
		$hoptime+10 : ($hoptime + int($self->{pingave}*10));
 
	# split up the 'rest' which are 'a=b' pairs separated by commas
    # and create a new thingy based on the class passed (if known)
	# ignore pairs with a leading '_'.

	my @par;

	for (split /;/, $rest) {
		next if /^_/;
		next unless /^\w+=/;
		s/\%([0-9A-F][0-9A-F])/chr(hex($1))/eg;
		push @par, split(/=/,$_,2);
	}
 
	no strict 'refs';
	my $pkg = 'Thingy::' . lcfirst $class;
	my $t = $pkg->new(_tonode=>$tonode, _fromnode=>$fromnode,
					  _msgid=>$msgid, _hoptime=>$newhoptime,
					  _newdata=>$rest, _inon=>$self->{call},
					  @par) if defined *$pkg && $pkg->can('new');
	$t->queue if $t;
	return;
}

my $last_node_update = 0;
my $node_update_interval = 60*60;

sub process
{
	if ($main::systime >= $last_node_update+$node_update_interval) {
		$last_node_update = $main::systime;
	}
}

sub disconnect
{
	my $self = shift;
	my $t = Thingy::Route->new_node_disconnect($main::mycall, $main::mycall, $self->{call});
	$t->queue;
	$self->DXProt::disconnect(@_);
}

my $msgid = 1;

sub nextmsgid
{
	my $r = $msgid;
	$msgid = 1 if ++$msgid > 99999;
	return $r;
}

sub node_update
{
	my $t = Thingy::Route->new_node_update();
	$t->queue if $t;
}

sub t_send
{
	my $self = shift;
	my $t = shift;
	confess('$t is not a Thingy') unless $t->isa('Thingy');
	
	# manufacture the protocol line if required
	unless (exists $t->{_newprot}) {
		my ($class) = ref $self =~ /::(\w+)$/;
		unless (exists $t->{_rest}) {
			$t->{_rest} = "";
			while (my ($k,$v) = each %$t) {
				next if $k =~ /^_/;
				if (ref $v && @$v) {
					my $val = "";
					for(@$v) {
						my $vv = $_;
						$vv =~ s/([\%;=,\x00-\x1f\x7f-\xff])/sprintf("%%%02X", ord($1))/eg;
						$val .= $vv . ',';
					}
					if (length $val) {
						chop $val;
						$t->{_rest} .= "$k=$val;";
					}
				} elsif (length $v) {
					$v =~ s/([\%;=\x00-\x1f\x7f-\xff])/sprintf("%%%02X", ord($1))/eg;
					$t->{_rest} .= "$k=$v;";
				}
			}
			chop $t->{_rest} if length $t->{_rest};
		}
		
		$t->{_hoptime} ||= 1;
		$t->{_msgid} = nextmsgid() unless $t->{_msgid};
		$t->{_newprot} = join(';', $t->{_tonode}, $t->{_fromnode}, uc $class,
							  $t->{_msgid}, $t->{_hoptime}) . '|' . $t->{_rest};
	}
	$self->SUPER::send($t->{_newprot});
}

1;
