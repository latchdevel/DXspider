There are the notes for upgrading to the mojo branch.

Prerequisites:

perl 5.10.1, preferably 5.14.1 or greater. This basically means running ubuntu 12.04 or later (or one of the other linux distros of similar age). The install instructions are for debian based systems.

cpamminus:

	sudo apt-get install cpanminus
or
	curl -L https://cpanmin.us | perl - --sudo App::cpanminus

You will need the following CPAN packages:

	sudo cpanm EV Mojolicious Mojo::IOLoop::ForkCall JSON JSON::XS

login as the sysop user.

Edit your /spider/local/DXVars.pm so that the bottom of the looks something like:

----  old ----

	  # the port number of the cluster (just leave this, unless it REALLY matters to you)
	  $clusterport = 27754;

	  # your favorite way to say 'Yes'
	  $yes = 'Yes';

	  # your favorite way to say 'No'
	  $no = 'No';

	  # the interval between unsolicited prompts if not traffic
	  $user_interval = 11*60;

	  # data files live in 
	  $data = "$root/data";

	  # system files live in
	  $system = "$root/sys";

	  # command files live in
	  $cmd = "$root/cmd";

	  # local command files live in (and overide $cmd)
	  $localcmd = "$root/local_cmd";

	  # where the user data lives
	  $userfn = "$data/users";

	  # the "message of the day" file
	  $motd = "$data/motd";

	  # are we debugging ?
	  @debug = qw(chan state msg cron );

---- to new ---

	 # the port number of the cluster (just leave this, unless it REALLY matters to you)
	 $clusterport = 27754;

	 # your favorite way to say 'Yes'
	 $yes = 'Yes';

	 # your favorite way to say 'No'
	 $no = 'No';

	 # this is where the paths used to be
	 
	 # are we debugging ?
	 @debug = qw(chan state msg cron );

----      ------

There may be other stuff after this in DXVars.pm, that doesn't matter. The point is to remove all the paths in DXVars.pm.

Now run the console program or telnet localhost and login as the sysop user.

	export_users
	bye

as the sysop user:

   sudo service dxspider stop
   mkdir /spider/local_data
   git reset --hard
   git pull
   git checkout --track -b mojo origin/mojo

if you have not already done this:

   sudo ln -s /spider/perl/console.pl /usr/local/bin/dx
   sudo ln -s /spider/perl/*dbg /usr/local/bin

Now in another window run:

	watchdbg

and finally:

   sudo service dxspider start






