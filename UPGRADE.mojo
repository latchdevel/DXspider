There are the notes for upgrading to the mojo branch.

There is NO POINT in doing this at the moment unless you are running a node with many (>50)
users. It is the future, but at the moment I am testing larger and larger installations to
check that it a) still works as people imagine it should and b) it provides the improvement
in scaling that I am anticipating. There are no significant new features - yet. 

The BIG TICKET ITEM in this branch is that (potentially) "long lived" commands such as sh/dx
and commands that poll external internet resources now don't halt the flow of data through
the node. I am also using a modern, event driven, web socket "manager" called Mojolicious
which is considerably more efficient than what went before (but is not necessary for small
nodes). There are some 200-400 user nodes out there that will definitely see the difference
in terms of both CPU usage and general responsiveness. Using Mojolicious also brings the
tantalising possibility of grafting on a web frontend, as it were, to the "side" of a
DXSpider node. But serious work on this won't start until we have a stable base to work
on. Apart from anything else there will, almost certainly, need to be some internal data
structure reorganisation before a decent web frontend could be constructed.

*IMPORTANT* There is an action needed to go from mojo build 228 and below. See items marked
*IMPORTANT* below. 

Upgrading is not for the faint of heart. There is no installation script (but there
will be) so, for the time being, you need to do some manual editing. Also, while there is
a backward path, it will involve moving various files from their new home (/spider/local_data),
back to where they came from (/spider/data).

Prerequisites:

	A supply of good, strong tea - preferably in pint mugs. A tin hat, stout boots, a
	rucksack with survival rations and a decent miners' lamp might also prove comforting. I
	enclose this link: http://www.noswearing.com/dictionary in case you run out of swear words.

	An installed and known working git based installation. Mojo is not supported under CVS or
	installation from a tarball. 

	perl 5.10.1, preferably 5.14.1 or greater. This basically means running ubuntu 12.04 or
	later (or one of the other linux distros of similar age or later). The install instructions are
	for debian based systems. IT WILL NOT WORK WITHOUT A "MODERN" PERL. Yes, you can use
	bleadperl if you know how to use it and can get it to run the node under it as a daemon
	without resorting the handy URL supplied above. Personally, I wouldn't bother. It's
	easier and quicker just to upgrade your linux distro. Apart from anything else things like ssh
	ntpd are broken on ALL older systems and will allow the ungodly in more easily than something
	modern.

Install cpamminus:

	sudo apt-get install cpanminus
or
    wget -O - https://cpanmin.us | perl - --sudo App::cpanminus
or
	sudo apt-get install curl
	curl -L https://cpanmin.us | perl - --sudo App::cpanminus

You will need the following CPAN packages:

	If you are on a Debian based system (Devuan, Ubuntu, Mint etc) that is reasonably new (I use Ubuntu
	18.04 and Debian 10) then you can simply do:

	sudo apt-get install libev-perl libmojolicious-perl libjson-perl libjson-xs-perl libdata-structure-util-perl

    or on Redhat based systems you can install the very similarly (but not the same) named
	packages. I don't the exact names but using anything less than Centos 7 is likely to cause
	a world of pain. Also I doubt that EV and Mojolicious are packaged for Centos at all.

	If in doubt or it is taking too long to find the packages you should build from CPAN. Note: you may
	need to install the essential packages to build some of these. At the very least you will need
	to install 'make' (sudo apt-get install make) or just get everything you are likely to need with:
	
	sudo apt-get install build-essential.

	sudo cpanm EV Mojolicious JSON JSON::XS Data::Structure::Util
	
	# just in case it's missing
	sudo apt-get install top

Please make sure that, if you insist on using operating system packages, that your Mojolicious is
at least version 7.26. Mojo::IOLoop::ForkCall is NOT LONGER IN USE! The current version at time
of writing is 8.36.

Login as the sysop user.

Edit your /spider/local/DXVars.pm so that the bottom of the file is changed from something like:

---- old ----

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

---- to this: ----

	 # the port number of the cluster (just leave this, unless it REALLY matters to you)
	 $clusterport = 27754;

	 # your favorite way to say 'Yes'
	 $yes = 'Yes';

	 # your favorite way to say 'No'
	 $no = 'No';

	 # this is where the paths used to be which you have just removed
	 
	 # are we debugging ?
	 @debug = qw(chan state msg cron );

---- new  ------

There may be other stuff after this in DXVars.pm, that doesn't matter. The point is to remove
all the path definitions in DXVars.pm. If this isn't clear to you then it would be better if
you asked on dxspider-support for help before attempting to go any further.

One of the things that will happen is that several files currently in /spider/data will be
placed in /spider/local_data. These include the user, qsl and usdb data files, the band and
prefix files, and various "bad" data files. I.e. everything that is modified from the base
git distribution. 

Now run the console program or telnet localhost and login as the sysop user.

	export_users
	bye

as the sysop user:

   sudo service dxspider stop
   or
   sudo systemctl stop dxspider

having stopped the node:

   mkdir /spider/local_data
   git reset --hard
   git pull
   git checkout --track -b mojo origin/mojo

if you have not already done this:

   sudo ln -s /spider/perl/console.pl /usr/local/bin/dx
   sudo ln -s /spider/perl/*dbg /usr/local/bin

*IMPORTANT* (for any build of dxspider) regardless of branch below build 229 run:

	/spider/perl/convert-users-v3-to-v4.pl
	
Now in another window run:

	watchdbg

and finally:

   sudo service dxspider start
   or
   sudo service systemctl start dxspider

You should be aware that this code base is now under active development and, if you do a 'git pull',
what you get may be broken. But, if this does happen, the likelihood is that I am actively working
on the codebase and any brokenness may be fixed (maybe in minutes) with another 'git pull'.

I try very hard not to leave it in a broken state...

Dirk G1TLH




