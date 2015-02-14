#
# DXSpider - The Web Interface
#
# Copyright (c) 2015 Dirk Koopman G1TLH
#

use strict;

package Web;

use Mojolicious::Lite;
use Mojo::IOLoop;
use DXDebug;

sub start_node
{
	Mojo::IOLoop->start unless Mojo::IOLoop->is_running;

	dbg("After Mojo::IOLoop");
}


1;
