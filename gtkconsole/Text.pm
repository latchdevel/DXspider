#
# create a text area with scroll bars
#
# Copyright (c) 2001 Dirk Koopman G1TLH
#
#
#

package Text;

use strict;
use Gtk;

use vars qw(@ISA);
@ISA = qw(Gtk::Text);

sub new
{
	my $pkg = shift;
	my ($vbar, $hbar) = @_;
	
	my $font = Gtk::Gdk::Font->load("-misc-fixed-medium-r-normal-*-*-130-*-*-c-*-koi8-r");
	my $text = new Gtk::Text(undef,undef);
	my $style = $text->style;
	$style->font($font);
	$text->set_style($style);
	$text->show;
	my $vscroll = new Gtk::VScrollbar($text->vadj);
	$vscroll->show;
	my $box = new Gtk::HBox();
	$box->add($text);
	$box->pack_start($vscroll, 0,0,0);
	$box->show;

	my $self = bless $box, $pkg;
	$self->{text} = $text;
	$self->{text}->{font} = $font;
	return $self;
}

sub destroy
{
	my $self = shift;
	delete $self->{text}->{font};
	delete $self->{text};
}

sub text
{
	return shift->{text};
}

1;
