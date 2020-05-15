#
# A light shim over Mojo::IOLoop::Subprocess (or Mojo::IOLoop::ForkCall, if we need to go back to that)
#
# But we stop using Storable!
#

package DXSubprocess;

use DXUtil;
use DXDebug;
use Mojo::IOLoop;
use	Mojo::IOLoop::Subprocess;
use JSON;

our @ISA = qw(Mojo::IOLoop::Subprocess);

sub new
{
	my $pkg = shift;
	my $class = ref $pkg || __PACKAGE__;
	my $ref = Mojo::IOLoop::Subprocess->new->serialize(\&encode_json)->deserialize(\&decode_json);
	return bless $ref, $class;
}
