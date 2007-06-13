#!/usr/bin/perl -w

package K4UTE;

use HTML::Parser;
use Data::Dumper;

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
	if ($tag eq 'tr' ) {
		if ($self->{state} eq 't1') {
			$self->state('t1r');
		} elsif ($self->{state} eq 't1r') {
			$self->state('t1d1');
		} elsif ($self->{state} eq 't2') {
			$self->state('t2r');
		} elsif ($self->{state} eq 't2r') {
			$self->state('t2d1');
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
			$self->state('t1');
			$self->{addr} = "";
			$self->{laddr} = 0;
		} elsif ($self->{state} eq 't1d1') {
			$self->{dxcall} = $text;
			$self->state('t1d2');
		} elsif ($self->{state} eq 't1d2') {
			$self->{dxmgr} = $text;
			$self->state('t1d3');
		} elsif ($self->{state} eq 't1d3') {
			$self->{dxdate} = amdate($text);
			$self->state('t1d4');
		} elsif ($self->{state} eq 't1d4') {
			push @{$self->{list}}, "$self->{dxcall}|mgr|$self->{dxmgr}|$self->{dxdate}|$text";
			$self->state('t1e');
		} elsif ($self->{state} eq 't2d1') {
			$self->{dxcall} = $text;
			$self->state('t2d2');
		} elsif ($self->{state} eq 't2d2') {
			$self->{dxaddr} = $text;
			$self->state('t2d3');
		} elsif ($self->{state} eq 't2d3') {
			$self->{dxdate} = amdate($text);
			$self->state('t2d4');
		} elsif ($self->{state} eq 't2d4') {
			push @{$self->{list}}, "$self->{dxcall}|addr|$self->{dxaddr}|$self->{dxdate}|$text";
			$self->state('t2e');
		} elsif ($self->{state} eq 't2' && $text =~ /did\s+not\s+return/i) {
			$self->state('last');
		}
	}
}

sub end
{
	my ($self, $tag, $origtext) = @_;
    print "$self->{state} /$tag\n" if $self->{debug};
	if ($self->{state} =~ /^t1/ && $tag eq 'table') {
		$self->state('t2');
	} elsif ($self->{state} =~ /^t2/ && $tag eq 'table') {
		$self->state('last');
	}
}

sub amdate
{
	my $text = shift;
	my ($m, $d, $y) = split m{/}, $text;
	$y += 1900;
	$y += 100 if $y < 1990;
	return sprintf "%02d-%s-%d", $d, (qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec))[$m-1], $y;
}

sub state
{
	my $self = shift;
	$self->{state} = shift if @_;
	return $self->{state};
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

