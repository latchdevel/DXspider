#
# Polled Timer handling
#
# This uses callbacks. BE CAREFUL!!!!
#
# $Id$
#
# Copyright (c) 2001 Dirk Koopman G1TLH
#

package Timer;

use vars qw(@timerchain $notimers);
use DXDebug;

@timerchain = ();
$notimers = 0;

sub new
{
    my ($pkg, $time, $proc, $recur) = @_;
	my $obj = ref($pkg);
	my $class = $obj || $pkg;
	my $self = bless { t=>$time + time, proc=>$proc }, $class;
	$self->{interval} = $time if $recur;
	push @timerchain, $self;
	$notimers++;
	dbg('connll', "Timer created ($notimers)");
	return $self;
}

sub del
{
	my $self = shift;
	delete $self->{proc};
	@timerchain = grep {$_ != $self} @timerchain;
}

sub handler
{
	my $now = time;
	
	# handle things on the timer chain
	for (@timerchain) {
		if ($now >= $_->{t}) {
			&{$_->{proc}}();
			$_->{t} = $now + $_->{interval} if exists $_->{interval};
		}
	}
}

sub DESTROY
{
	dbg('connll', "Timer destroyed ($notimers)");
	$notimers--;
}
1;
