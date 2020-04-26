#
# various utilities which are exported globally
#
# Copyright (c) 1998 - Dirk Koopman G1TLH
#
#
#

package DXUtil;


use Date::Parse;
use IO::File;
use File::Copy;
use Data::Dumper;
use Time::HiRes qw(gettimeofday tv_interval);

use strict;

use vars qw(@month %patmap $pi $d2r $r2d @ISA @EXPORT);

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(atime ztime cldate cldatetime slat slong yesno promptf 
			 parray parraypairs phex phash shellregex readfilestr writefilestr
			 filecopy ptimelist
             print_all_fields cltounix unpad is_callsign is_latlong
			 is_qra is_freq is_digits is_pctext is_pcflag insertitem deleteitem
			 is_prefix dd is_ipaddr $pi $d2r $r2d localdata localdata_mv
			 diffms _diffms
            );


@month = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
%patmap = (
		   '*' => '.*',
		   '?' => '.',
		   '[' => '[',
		   ']' => ']'
);

$pi = 3.141592653589;
$d2r = ($pi/180);
$r2d = (180/$pi);


# a full time for logging and other purposes
sub atime
{
	my $t = shift;
	my ($sec,$min,$hour,$mday,$mon,$year) = gmtime((defined $t) ? $t : time);
	$year += 1900;
	my $buf = sprintf "%02d%s%04d\@%02d:%02d:%02d", $mday, $month[$mon], $year, $hour, $min, $sec;
	return $buf;
}

# get a zulu time in cluster format (2300Z)
sub ztime
{
	my $t = shift;
	$t = defined $t ? $t : time;
	my $dst = shift;
	my ($sec,$min,$hour) = $dst ? localtime($t): gmtime($t);
	my $buf = sprintf "%02d%02d%s", $hour, $min, ($dst) ? '' : 'Z';
	return $buf;
}

# get a cluster format date (23-Jun-1998)
sub cldate
{
	my $t = shift;
	$t = defined $t ? $t : time;
	my $dst = shift;
	my ($sec,$min,$hour,$mday,$mon,$year) = $dst ? localtime($t) : gmtime($t);
	$year += 1900;
	my $buf = sprintf "%2d-%s-%04d", $mday, $month[$mon], $year;
	return $buf;
}

# return a cluster style date time
sub cldatetime
{
	my $t = shift;
	my $dst = shift;
	my $date = cldate($t, $dst);
	my $time = ztime($t, $dst);
	return "$date $time";
}

# return a unix date from a cluster date and time
sub cltounix
{
	my $date = shift;
	my $time = shift;
	my ($thisyear) = (gmtime)[5] + 1900;

	return 0 unless $date =~ /^\s*(\d+)-(\w\w\w)-([12][90]\d\d)$/;
	return 0 if $3 > 2036;
	return 0 unless abs($thisyear-$3) <= 1;
	$date = "$1 $2 $3";
	return 0 unless $time =~ /^([012]\d)([012345]\d)Z$/;
	$time = "$1:$2 +0000";
	my $r = str2time("$date $time");
	return $r unless $r;
	return $r == -1 ? undef : $r;
}

# turn a latitude in degrees into a string
sub slat
{
	my $n = shift;
	my ($deg, $min, $let);
	$let = $n >= 0 ? 'N' : 'S';
	$n = abs $n;
	$deg = int $n;
	$min = int ((($n - $deg) * 60) + 0.5);
	return "$deg $min $let";
}

# turn a longitude in degrees into a string
sub slong
{
	my $n = shift;
	my ($deg, $min, $let);
	$let = $n >= 0 ? 'E' : 'W';
	$n = abs $n;
	$deg = int $n;
	$min = int ((($n - $deg) * 60) + 0.5);
	return "$deg $min $let";
}

# turn a true into 'yes' and false into 'no'
sub yesno
{
	my $n = shift;
	return $n ? $main::yes : $main::no;
}

# provide a data dumpered version of the object passed
sub dd
{
	my $value = shift;
	my $dd = new Data::Dumper([$value]);
	$dd->Indent(0);
	$dd->Terse(1);
    $dd->Quotekeys($] < 5.005 ? 1 : 0);
	$value = $dd->Dumpxs;
	$value =~ s/([\r\n\t])/sprintf("%%%02X", ord($1))/eg;
	$value =~ s/^\s*\[//;
    $value =~ s/\]\s*$//;
	
	return $value;
}

# format a prompt with its current value and return it with its privilege
sub promptf
{
	my ($line, $value) = @_;
	my ($priv, $prompt, $action) = split ',', $line;

	# if there is an action treat it as a subroutine and replace $value
	if ($action) {
		my $q = qq{\$value = $action(\$value)};
		eval $q;
	} elsif (ref $value) {
		$value = dd($value);
	}
	$prompt = sprintf "%15s: %s", $prompt, $value;
	return ($priv, $prompt);
}

# turn a hex field into printed hex
sub phex
{
	my $val = shift;
	return sprintf '%X', $val;
}

# take an arg as a hash of call=>time pairs and print it
sub ptimelist
{
	my $ref = shift;
	my $out;
	for (sort keys %$ref) {
		$out .= "$_=$ref->{$_}, ";
	}
	chop $out;
	chop $out;
	return $out;	
}

# take an arg as an array list and print it
sub parray
{
	my $ref = shift;
	return ref $ref ? join(', ', @{$ref}) : $ref;
}

# take the arg as an array reference and print as a list of pairs
sub parraypairs
{
	my $ref = shift;
	my $i;
	my $out;

	for ($i = 0; $i < @$ref; $i += 2) {
		my $r1 = @$ref[$i];
		my $r2 = @$ref[$i+1];
		$out .= "$r1-$r2, ";
	}
	chop $out;					# remove last space
	chop $out;					# remove last comma
	return $out;
}

# take the arg as a hash reference and print it out as such
sub phash
{
	my $ref = shift;
	my $out;

	while (my ($k,$v) = each %$ref) {
		$out .= "${k}=>$v, ";
	}
	chop $out;					# remove last space
	chop $out;					# remove last comma
	return $out;
}

sub _sort_fields
{
	my $ref = shift;
	my @a = split /,/, $ref->field_prompt(shift); 
	my @b = split /,/, $ref->field_prompt(shift); 
	return lc $a[1] cmp lc $b[1];
}

# print all the fields for a record according to privilege
#
# The prompt record is of the format '<priv>,<prompt>[,<action>'
# and is expanded by promptf above
#
sub print_all_fields
{
	my $self = shift;			# is a dxchan
	my $ref = shift;			# is a thingy with field_prompt and fields methods defined
	my @out;
	my @fields = $ref->fields;
	my $field;
	my $width = $self->width - 1;
	$width ||= 80;

	foreach $field (sort {_sort_fields($ref, $a, $b)} @fields) {
		if (defined $ref->{$field}) {
			my ($priv, $ans) = promptf($ref->field_prompt($field), $ref->{$field});
			my @tmp;
			if (length $ans > $width) {
				my ($p, $a) = split /: /, $ans, 2;
				my $l = (length $p) + 2;
				my $al = ($width - 1) - $l;
				my $bit;
				while (length $a > $al ) {
					($bit, $a) = unpack "A$al A*", $a;
					push @tmp, "$p: $bit";
					$p = ' ' x ($l - 2);
				}
				push @tmp, "$p: $a" if length $a;
			} else {
				push @tmp, $ans;
			}
			push @out, @tmp if ($self->priv >= $priv);
		}
	}
	return @out;
}

# generate a regex from a shell type expression 
# see 'perl cookbook' 6.9
sub shellregex
{
	my $in = shift;
	$in =~ s{(.)} { $patmap{$1} || "\Q$1" }ge;
	return '^' . $in . "\$";
}

# read in a file into a string and return it. 
# the filename can be split into a dir and file and the 
# file can be in upper or lower case.
# there can also be a suffix
sub readfilestr
{
	my ($dir, $file, $suffix) = @_;
	my $fn;
	my $f;
	if ($suffix) {
		$f = uc $file;
		$fn = "$dir/$f.$suffix";
		unless (-e $fn) {
			$f = lc $file;
			$fn = "$dir/$file.$suffix";
		}
	} elsif ($file) {
		$f = uc $file;
		$fn = "$dir/$file";
		unless (-e $fn) {
			$f = lc $file;
			$fn = "$dir/$file";
		}
	} else {
		$fn = $dir;
	}

	my $fh = new IO::File $fn;
	my $s = undef;
	if ($fh) {
		local $/ = undef;
		$s = <$fh>;
		$fh->close;
	}
	return $s;
}

# write out a file in the format required for reading
# in via readfilestr, it expects the same arguments 
# and a reference to an object
sub writefilestr
{
	my $dir = shift;
	my $file = shift;
	my $suffix = shift;
	my $obj = shift;
	my $fn;
	my $f;
	
	confess('no object to write in writefilestr') unless $obj;
	confess('object not a reference in writefilestr') unless ref $obj;
	
	if ($suffix) {
		$f = uc $file;
		$fn = "$dir/$f.$suffix";
		unless (-e $fn) {
			$f = lc $file;
			$fn = "$dir/$file.$suffix";
		}
	} elsif ($file) {
		$f = uc $file;
		$fn = "$dir/$file";
		unless (-e $fn) {
			$f = lc $file;
			$fn = "$dir/$file";
		}
	} else {
		$fn = $dir;
	}

	my $fh = new IO::File ">$fn";
	if ($fh) {
		my $dd = new Data::Dumper([ $obj ]);
		$dd->Indent(1);
		$dd->Terse(1);
		$dd->Quotekeys(0);
		#	$fh->print(@_) if @_ > 0;     # any header comments, lines etc
		$fh->print($dd->Dumpxs);
		$fh->close;
	}
}

sub filecopy
{
	copy(@_) or return $!;
}

# remove leading and trailing spaces from an input string
sub unpad
{
	my $s = shift;
	$s =~ s/\s+$//;
	$s =~ s/^\s+//;
	return $s;
}

# check that a field only has callsign characters in it
sub is_callsign
{
	return $_[0] =~ m!^
					  (?:\d?[A-Z]{1,2}\d*/)?    # out of area prefix /  
					  (?:\d?[A-Z]{1,2}\d+)      # main prefix one (required) 
					  [A-Z]{1,5}                # callsign letters (required)
					  (?:-(?:\d{1,2}|\#))?      # - nn possibly (eg G8BPQ-8) or -# (an RBN spot) 
					  (?:/[0-9A-Z]{1,7})?       # / another prefix, callsign or special label (including /MM, /P as well as /EURO or /LGT) possibly
					  $!x;

	# longest callign allowed is 1X11/1Y11XXXXX-11/XXXXXXX
}

sub is_prefix
{
	return $_[0] =~ m!^(?:[A-Z]{1,2}\d+ | \d[A-Z]{1,2}}\d+)!x        # basic prefix
}
	

# check that a PC protocol field is valid text
sub is_pctext
{
	return undef unless length $_[0];
	return undef if $_[0] =~ /[\x00-\x08\x0a-\x1f\x80-\x9f]/;
	return 1;
}

# check that a PC prot flag is fairly valid (doesn't check the difference between 1/0 and */-)
sub is_pcflag
{
	return $_[0] =~ /^[01\*\-]+$/;
}

# check that a thing is a frequency
sub is_freq
{
	return $_[0] =~ /^\d+(?:\.\d+)?$/;
}

# check that a thing is just digits
sub is_digits
{
	return $_[0] =~ /^[\d]+$/;
}

# does it look like a qra locator?
sub is_qra
{
	return unless length $_[0] == 4 || length $_[0] == 6;
	return $_[0] =~ /^[A-Ra-r][A-Ra-r]\d\d(?:[A-Xa-x][A-Xa-x])?$/;
}

# does it look like a valid lat/long
sub is_latlong
{
	return $_[0] =~ /^\s*\d{1,2}\s+\d{1,2}\s*[NnSs]\s+1?\d{1,2}\s+\d{1,2}\s*[EeWw]\s*$/;
}

# is it an ip address?
sub is_ipaddr
{
    return $_[0] =~ /^\d+\.\d+\.\d+\.\d+$/ || $_[0] =~ /^[0-9a-f:,]+$/;
}

# insert an item into a list if it isn't already there returns 1 if there 0 if not
sub insertitem
{
	my $list = shift;
	my $item = shift;
	
	return 1 if grep {$_ eq $item } @$list;
	push @$list, $item;
	return 0;
}

# delete an item from a list if it is there returns no deleted 
sub deleteitem
{
	my $list = shift;
	my $item = shift;
	my $n = @$list;
	
	@$list = grep {$_ ne $item } @$list;
	return $n - @$list;
}

# find the correct local_data directory
# basically, if there is a local_data directory with this filename and it is younger than the
# equivalent one in the (system) data directory then return that name rather than the system one
sub localdata
{
	my $ifn = shift;
	my $ofn = "$main::local_data/$ifn";
	my $tfn;
	
	if (-e "$main::local_data") {
		$tfn = "$main::data/$ifn";
		if (-e $tfn && -e $ofn) {
			$ofn = $tfn if -M $ofn < -M $tfn;
		} elsif (-e tfn) {
			$ofn = $tfn;
		}
	}

	return $ofn;
}

# move a file or a directory from data -> local_data if isn't there already
sub localdata_mv
{
	my $ifn = shift;
	if (-e "$main::data/$ifn" ) {
		unless (-e "$main::local_data/$ifn") {
			move("$main::data/$ifn", "$main::local_data/$ifn") or die "localdata_mv: cannot move $ifn from '$main::data' -> '$main::local_data' $!\n";
		}
	}
}

# measure the time taken for something to happen; use Time::HiRes qw(gettimeofday tv_interval);
sub _diffms
{
	my $ta = shift;
	my $tb = shift || [gettimeofday];
	my $a = int($ta->[0] * 1000) + int($ta->[1] / 1000); 
	my $b = int($tb->[0] * 1000) + int($tb->[1] / 1000);
	return $b - $a;
}

sub diffms
{
	my $call = shift;
	my $line = shift;
	my $ta = shift;
	my $no = shift;
	my $tb = shift;
	my $msecs = _diffms($ta, $tb);

	$line =~ s|\s+$||;
	my $s = "subprocess stats cmd: '$line' $call ${msecs}mS";
	$s .= " $no lines" if $no;
	DXDebug::dbg($s);
}
