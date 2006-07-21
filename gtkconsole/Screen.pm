#
# Generic screen generator
# 
# This produces the Gtk for all the little sub-screens
#
# $Id$
#
# Copyright (c) 2006 Dirk Koopman G1TLH
#

use strict;

package Screen;

use Gtk2;
use Gtk2::SimpleList;
use Text::Wrap;

INIT {
	Gtk2::SimpleList->add_column_type( 'qrg',
									   type     => 'Glib::Scalar',
									   renderer => 'Gtk2::CellRendererText',
									   attr     => sub {
										   my ($treecol, $cell, $model, $iter, $col_num) = @_;
										   my $info = $model->get ($iter, $col_num);
										   $cell->set(text => sprintf("%.1f", $info), xalign => 1.0);
									   }
									 );
	
	
	Gtk2::SimpleList->add_column_type( 'tt',
									   type     => 'Glib::Scalar',
									   renderer => 'Gtk2::CellRendererText',
									   attr     => sub {
										   my ($treecol, $cell, $model, $iter, $col_num) = @_;
										   my $info = $model->get ($iter, $col_num);
										   $cell->set(text => $info);
									   }
									 );

	Gtk2::SimpleList->add_column_type( 'ttlong',
									   type     => 'Glib::Scalar',
									   renderer => 'Gtk2::CellRendererText',
									   attr     => sub {
										   my ($treecol, $cell, $model, $iter, $col_num) = @_;
										   my $info = $model->get ($iter, $col_num);
										   $Text::Wrap::columns = 80;
										   $cell->set(text => join("\n",wrap("","",$info)));
									   }
									 );

	Gtk2::SimpleList->add_column_type( 'ttlesslong',
									   type     => 'Glib::Scalar',
									   renderer => 'Gtk2::CellRendererText',
									   attr     => sub {
										   my ($treecol, $cell, $model, $iter, $col_num) = @_;
										   my $info = $model->get ($iter, $col_num);
										   $Text::Wrap::columns = 65;
										   $cell->set(text => join("\n",wrap("","",$info)));
									   }
									 );

	Gtk2::SimpleList->add_column_type( 'ttshort',
									   type     => 'Glib::Scalar',
									   renderer => 'Gtk2::CellRendererText',
									   attr     => sub {
										   my ($treecol, $cell, $model, $iter, $col_num) = @_;
										   my $info = $model->get ($iter, $col_num);
										   $Text::Wrap::columns = 30;
										   $cell->set(text => join("\n",wrap("","",$info)));
									   }
									 );

}

sub new
{
	my $pkg = shift;
	my $class = ref $pkg || $pkg;
	return bless {@_}, $class;
}

sub widget
{
	return $_[0]->{widget};
}

1;

package Screen::List;

our @ISA = qw(Screen);

sub _row_inserted
{
	my ($liststore, $path, $iter, $self) = @_;
	$self->{list}->scroll_to_cell($path);
}

sub new
{
	my $pkg = shift;
	my %args = @_;
	
	my $list = Gtk2::SimpleList->new(@{$args{fields}});
	$list->set_rules_hint(1) if $args{hint};
	$list->set_name($args{pkgname} || __PACKAGE__);
	
	my $scroll = Gtk2::ScrolledWindow->new (undef, undef);
	$scroll->set_shadow_type ($args{shadow_type} || 'etched-out');
	$scroll->set_policy (exists $args{policy} ? @{$args{policy}} : qw(automatic automatic));
	$scroll->set_size_request (@{$args{size}}) if exists $args{size};
	$scroll->add($list);
	$scroll->set_border_width(exists $args{border_width} ? $args{border_width} : 2);
	
	my $self = $pkg->SUPER::new(scroller => $scroll, list => $list, widget => $scroll, maxsize => ($args{maxsize} || 100));

	$list->get_model->signal_connect('row-inserted', \&_row_inserted, $self);

	if ($args{frame}) {
		my $frame = Gtk2::Frame->new($args{frame});
		$frame->add($scroll);
		$self->{widget} = $self->{frame} = $frame;
	}
	return $self;
}

sub add_data
{
	my $self = shift;
	my $list = $self->{list};
	
	push @{$list->{data}}, ref $_[0] ? $_[0] : [ @_ ];
	shift @{$list->{data}} if @{$list->{data}} > $self->{maxsize};
}
1;
