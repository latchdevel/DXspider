#
# Gtk Handler for Debug Files
#

package DebugHandler;

use strict;

use Gtk;
use DXVars;
use DXLog;
use DXUtil;

use vars qw(@ISA);
@ISA = qw(Gtk::Window);

sub new
{
	my $pkg = shift;
	my $parent = shift;
	my $regexp = shift || '';
	my $nolines = shift || 1;
	
	my $self = new Gtk::Window;
	bless  $self, $pkg;
	$self->set_default_size(400, 400);
	$self->set_transient_for($parent) if $parent;
	$self->signal_connect('destroy', sub {$self->destroy} );
	$self->signal_connect('delete_event', sub {$self->destroy; return undef;});
	$self->set_title("Debug Output - $regexp");
	$self->border_width(0);
	$self->show;
	
	my $box1 = new Gtk::VBox(0, 0);
	$self->add($box1);
	$box1->show;
	
	my $swin = new Gtk::ScrolledWindow(undef, undef);
	$swin->set_policy('automatic', 'automatic');
	$box1->pack_start($swin, 1, 1, 0);
	$swin->show;
	
	my $button = new Gtk::Button('close');
	$button->signal_connect('clicked', sub {$self->destroy});
	$box1->pack_end($button, 0, 1, 0);
	$button->show;
	
	my $clist = new_with_titles Gtk::CList('Time', 'Data');
	$swin->add($clist);
	$clist->show;
	
	$self->{fp} = DXLog::new('debug', 'dat', 'd');
	
	my @today = Julian::unixtoj(time);
	my $fh = $self->{fh} = $self->{fp}->open(@today);
	$fh->seek(0, 2);
	$self->{regexp} = $regexp if $regexp;
	$self->{nolines} = $nolines;
	$self->{clist} = $clist;

	$self->{id} = Gtk::Gdk->input_add($fh->fileno, ['read'], sub {$self->handleinp(@_); 1;}, $fh);
	
	$self->show_all;
	return $self;
}

sub destroy
{
	my $self = shift;
	$self->{fp}->close;
	Gtk::Gdk->input_remove($self->{id});
	delete $self->{clist};
}

sub handleinp
{
	my ($self, $socket, $fd, $flags) = @_;
	if ($flags->{read}) {
		my $offset = exists $self->{rbuf} ? length $self->{rbuf} : 0; 
		my $l = sysread($socket, $self->{rbuf}, 1024, $offset);
		if (defined $l) {
			if ($l) {
				while ($self->{rbuf} =~ s/^([^\015\012]*)\015?\012//) {
					my $line = $1;
					if ($self->{regexp}) {
						push @{$self->{prev}}, $line;
						shift @{$self->{prev}} while @{$self->{prev}} > $self->{nolines}; 
						if ($line =~ m{$self->{regexp}}oi) {
							$self->printit(@{$self->{prev}});	
							@{$self->{prev}} = [];
						}
					} else {
						$self->printit($line);
					}
				}
			}
		}
	}
}

sub printit
{
	my $self = shift;
	my $clist = $self->{clist};
	while (@_) {
		my $line = shift;
		$line =~ s/([\x00-\x1f\x7f-\xff])/sprintf("\\x%02X", ord($1))/eg; 
		my @line =  split /\^/, $line, 2;
		my $t = shift @line;
		my ($sec,$min,$hour) = gmtime((defined $t) ? $t : time);
		my $buf = sprintf "%02d:%02d:%02d", $hour, $min, $sec;
		$clist->append($buf, @line);
	}
}
1;
