#
# A light shim over Mojo::IOLoop::Subprocess (or Mojo::IOLoop::ForkCall, if we need to go back to that)
#
# But we stop using Storable!
#

package DXSubprocess;

use DXUtil;
use DXDebug;
use DXLog;
use Mojo::IOLoop;
use	Mojo::IOLoop::Subprocess;
use JSON;

our @ISA = qw(Mojo::IOLoop::Subprocess);

sub new
{
	my $pkg = shift;
	my $class = ref $pkg || __PACKAGE__;
	my $ref = Mojo::IOLoop::Subprocess->new->serialize(\&freeze)->deserialize(\&thaw);
	return bless $ref, $class;
}

sub freeze
{
	my $r;
	my $j = shift;
	unless ($j) {
		LogDbg('DXUser', "DXSubcommand::freeze: undefined or empty input");
		return q{[null, ""]};
	}
	
	eval { $r = encode_json($j) };
	if ($@) {
		my $dd = dd($j);
		LogDbg('DXUser', "DXSubcommand::freeze: json error on '$dd': $@");
		$r = qq{['$@','']};
	}
	return $r;
}

sub thaw
{
	my $r;
	my $j = shift;
	unless ($j) {
		LogDbg('DXUser', "DXSubcommand::thaw: empty string on input");
		return q{[null, ""]};
	}

	return [undef, [1]] unless $j; 
	eval { $r = decode_json($j) };
	if ($@) {
		LogDbg('DXUser', "DXSubcommand::thaw: json error on '$j': $@");
		$r = qq{[$@,[1]]};
	}
	return $r;
}
1;

	
