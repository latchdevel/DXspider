#!/usr/bin/perl -w

package QRZ;

use HTML::Parser;
use Data::Dumper;

@ISA = qw( HTML::Parser );

use strict;


use vars qw($VERSION $BRANCH);
$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /\d+\.\d+\.(\d+)\.(\d+)/,(0,0));
$main::build += $VERSION;
$main::branch += $BRANCH;

sub new
{
    my $pkg = shift;
	my $self = SUPER::new $pkg;
	$self->{list} = [];
	$self->{state} = 'pre';
    $self->{sort} = undef;
	$self->{debug} = 0;
    $self->{call} = uc shift;
	return $self;
}

sub start
{
	my ($self, $tag, $attr, $attrseq, $origtext) = @_;
	if ($self->{debug}) {
		print "$self->{state} $tag";
        if ($attr) {
			my $dd = new Data::Dumper([$attr], [qw(attr)]);
			$dd->Terse(1);
			$dd->Indent(0);
			$dd->Quotekeys(0);
			print " ", $dd->Dumpxs;
		}
		print "\n";
	}
	if ($self->{state} eq 'addr') {
		if ($tag eq 'br') {
			$self->{addr} .= ", " if length $self->{addr} > $self->{laddr};
			$self->{laddr} = length $self->{addr};
		} elsif ($tag eq 'p') {
            push @{$self->{list}}, $self->{addr} ? "$self->{call}|addr|$self->{addr}" : "$self->{call}|addr|unknown";
			$self->state('semail');
		}
	} elsif ($self->{state} eq 'email') {
		if ($tag eq 'a') {
			my $email = $attr->{href};
			if ($email) {
				return if $email =~ m{/uedit.html};
				$email =~ s/mailto://i;
				push @{$self->{list}}, "$self->{call}|email|$email";
			}
		} elsif ($tag eq 'br' || $tag eq 'p') {
			$self->state('post');
		}
	}
}

sub text
{
	my ($self, $text) = @_;
	$text =~ s/^[\s\r\n]+//g;
	$text =~ s/[\s\r\n]+$//g;
    print "$self->{state} text $text\n" if $self->{debug};	
	if (length $text) {
		if ($self->{state} eq 'pre' && $text =~ /$self->{call}/i ) {
			$self->state('addr');
			$self->{addr} = "";
			$self->{laddr} = 0;
		} elsif ($self->{state} eq 'addr') {
			$text =~ s/\&nbsp;//gi;
			$self->{addr} .= $text;
		} elsif ($self->{state} eq 'semail' && $text =~ /Email/i ) {
			$self->state('email');
		}
	}
}

sub state
{
	my $self = shift;
	$self->{state} = shift if @_;
	return $self->{state};
}

sub end
{
	my ($self, $tag, $origtext) = @_;
    print "$self->{state} /$tag\n" if $self->{debug};
}

sub debug
{
	my ($self, $val) = @_;
	$self->{debug} = $val;
}

sub answer
{
	my $self = shift;
	return @{$self->{list}};
}

1;

