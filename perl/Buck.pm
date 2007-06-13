#!/usr/bin/perl -w

package Buck;

use HTML::Parser;
use Data::Dumper;
use DXUtil;

@ISA = qw( HTML::Parser );

use strict;

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
	if ($self->{state} eq 'pre' && $tag eq 'table') {
		$self->state('t1');
	} elsif ($self->{state} eq 't1' && $tag eq 'table') {
		$self->state('t2');
	} elsif ($self->{state} eq 't2' && $tag =~ /^h/) {
		$self->{addr} = "";
		$self->{laddr} = 0;
		$self->state('addr');
	} elsif ($self->{state} eq 'addr') {
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
			if ($email && $email =~ /mailto/i) {
				$email =~ s/mailto://i;
				push @{$self->{list}}, "$self->{call}|email|$email";
			}
		} elsif ($tag eq 'br' || $tag eq 'p') {
			$self->state('post');
		}
	} elsif ($self->{state} eq 'post' && $tag eq 'form') {
		if (exists $self->{pos} && length $self->{pos}) {
			push @{$self->{list}}, "$self->{call}|location|$self->{pos}";
			$self->state('last');
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
		if ($self->{state} eq 'addr') {
			$text =~ s/\&nbsp;//gi;
			$self->{addr} .= $text;
		} elsif ($self->{state} eq 'semail' && $text =~ /Email/i ) {
			$self->state('email');
		} elsif ($self->{state} eq 'post') {
			if ($text =~ /Latitude/i) {
				$self->state('lat');
				$self->{pos} = "" unless $self->{pos};
			} elsif ($text =~ /Longitude/i) {
				$self->state('long');
				$self->{pos} = "" unless $self->{pos};
			} elsif ($text =~ /Grid/i) {
				$self->state('grid');
				$self->{pos} = "" unless $self->{pos};
			}
		} elsif ($self->{state} eq 'lat') {
			my ($n, $l) = $text =~ /(\b[\d\.]+\b)\s+([NSns])/;
			$n = -$n if $l eq 'S' || $l eq 's';
			$self->{pos} = slat($n);
			$self->state('post');
		} elsif ($self->{state} eq 'long') {
			my ($n, $l) = $text =~ /(\b[\d\.]+\b)\s+([EWew])/;
			$n = -$n if $l eq 'W' || $l eq 'w';
			$self->{pos} .= "|" . slong($n);
			$self->state('post');
		} elsif ($self->{state} eq 'grid') {
			my ($qra) = $text =~ /(\b\w\w\d\d\w\w\b)/;
			$self->{pos} .= "|" . uc $qra;
			push @{$self->{list}}, "$self->{call}|location|$self->{pos}";
			$self->state('last');
		} elsif (($self->{state} eq 'pre' || $self->{state} =~ /^t/) && $text =~ /not\s+found/) {
            push @{$self->{list}}, "$self->{call}|addr|unknown";
			$self->state('last');
		} elsif ($self->{state} eq 'email' && $text =~ /unknown/i) {
			$self->state('post');
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

