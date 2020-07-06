6th July 2020

The latest release of the Mojo branch of DXSpider contains a client
for the Reverse Beacon Network (RBN). This is not a simple client, it
attempts to make some sense of the 10s of 1000s of "spots" that the
RBN can send PER HOUR. At busy times, actually nearly all the time, the
spots from the RBN come in too quickly for anybody to get anything more
than a fleeting impression of what's coming in.

Something has to try to make this manageable - which is what I have
tried to do with DXSpider's RBN client.

The RBN has a number of problems (apart from the overwhelming quantity
of data that it sends):

* Spotted callsigns, especially on CW, are not reliably
  decoded. Estimates vary as to how bad it is but, as far as I can
  tell, even these estimates are unreliable!

* The frequency given is unreliable. I have seen differences as great
  as 600hz on CW spots.

* There is far too much (in my view) useless information in each spot
  - even if one had time to read, decode and understand it before the
  spot has scrolled off the top of the screen.

* The format of the comment is not regular. If one has both FTx and
  "all the other" spots (CW, PSK et al) enabled at the same time,
  one's eye is constantly having to re-adjust. Again, very difficult
  to deal with on contest days. Especially if it mixed in with
  "normal" spots.

So what have I done about this? Look at the sample of input traffic
below:

05Jul2020@22:59:31 (chan) <- I SK0MMR DX de KM3T-2-#:  14100.0  CS3B           CW    24 dB  22 WPM  NCDXF B 2259Z
05Jul2020@22:59:31 (chan) <- I SK0MMR DX de KM3T-2-#:  28263.9  AB8Z/B         CW    15 dB  18 WPM  BEACON  2259Z
05Jul2020@22:59:31 (chan) <- I SK0MMR DX de LZ3CB-#:   7018.20  RW1M           CW    10 dB  18 WPM  CQ      2259Z
05Jul2020@22:59:31 (chan) <- I SK0MMR DX de W9XG-#:    14057.6  K7GT           CW     7 dB  21 WPM  CQ      2259Z
05Jul2020@22:59:31 (chan) <- I SK0MMR DX de G0LUJ-#:   14100.1  CS3B           CW    18 dB  20 WPM  NCDXF B 2259Z
05Jul2020@22:59:32 (chan) <- I SK0MMR DX de LZ4UX-#:    7018.3  RW1M           CW    13 dB  18 WPM  CQ      2259Z
05Jul2020@22:59:32 (chan) <- I SK0MMR DX de LZ4AE-#:    7018.3  RW1M           CW    28 dB  18 WPM  CQ      2259Z
05Jul2020@22:59:32 (chan) <- I SK0MMR DX de W1NT-6-#:  28222.9  N1NSP/B        CW     5 dB  15 WPM  BEACON  2259Z
05Jul2020@22:59:32 (chan) <- I SK0MMR DX de W1NT-6-#:  28297.0  NS9RC          CW     4 dB  13 WPM  BEACON  2259Z
05Jul2020@22:59:32 (chan) <- I SK0MMR DX de F8DGY-#:    7018.2  RW1M           CW    23 dB  18 WPM  CQ      2259Z
05Jul2020@22:59:33 (chan) <- I SK0MMR DX de 9A1CIG-#:  7018.30  RW1M           CW    20 dB  18 WPM  CQ      2259Z
05Jul2020@22:59:33 (chan) <- I SK0MMR DX de LZ7AA-#:    7018.3  RW1M           CW    16 dB  18 WPM  CQ      2259Z
05Jul2020@22:59:33 (chan) <- I SK0MMR DX de DK9IP-#:    7018.2  RW1M           CW    21 dB  18 WPM  CQ      2259Z
05Jul2020@22:59:33 (chan) <- I SK0MMR DX de WE9V-#:    10118.0  N5JCB          CW    15 dB  10 WPM  CQ      2259Z
05Jul2020@22:59:34 (chan) <- I SK0MMR DX de DJ9IE-#:    7028.0  PT7KM          CW    15 dB  10 WPM  CQ      2259Z
05Jul2020@22:59:34 (chan) <- I SK0MMR DX de DJ9IE-#:    7018.3  RW1M           CW    31 dB  18 WPM  CQ      2259Z
05Jul2020@22:59:34 (chan) <- I SK0MMR DX de DD5XX-#:    7018.3  RW1M           CW    21 dB  18 WPM  CQ      2259Z
05Jul2020@22:59:34 (chan) <- I SK0MMR DX de DE1LON-#:  14025.5  EI5JF          CW    13 dB  19 WPM  CQ      2259Z
05Jul2020@22:59:34 (chan) <- I SK0MMR DX de DE1LON-#:   7018.3  RW1M           CW    24 dB  18 WPM  CQ      2259Z
05Jul2020@22:59:34 (chan) <- I SK0MMR DX de ON6ZQ-#:    7018.3  RW1M           CW    22 dB  18 WPM  CQ      2259Z
05Jul2020@22:59:34 (chan) <- I SK0MMR DX de OH6BG-#:    3516.9  RA1AFT         CW    15 dB  25 WPM  CQ      2259Z
05Jul2020@22:59:35 (chan) <- I SK0MMR DX de HA1VHF-#:   7018.3  RW1M           CW    30 dB  18 WPM  CQ      2259Z
05Jul2020@22:59:35 (chan) <- I SK0MMR DX de F6IIT-#:    7018.4  RW1M           CW    32 dB  18 WPM  CQ      2259Z
05Jul2020@22:59:36 (chan) <- I SK0MMR DX de HB9BXE-#:   7018.3  RW1M           CW    23 dB  18 WPM  CQ      2259Z
05Jul2020@22:59:37 (chan) <- I SK0MMR DX de SM0IHR-#:   7018.3  RW1M           CW    21 dB  18 WPM  CQ      2259Z
05Jul2020@22:59:37 (chan) <- I SK0MMR DX de DK0TE-#:    7018.3  RW1M           CW    26 dB  18 WPM  CQ      2259Z
05Jul2020@22:59:37 (chan) <- I SK0MMR DX de OE9GHV-#:   7018.3  RW1M           CW    40 dB  19 WPM  CQ      2259Z
05Jul2020@22:59:37 (chan) <- I SK0MMR DX de CX6VM-#:   10118.0  N5JCB          CW    20 dB  10 WPM  CQ      2259Z
05Jul2020@22:59:37 (chan) -> D G1TST DX de F8DGY-#:     7018.3 RW1M         CW  23dB Q:9* Z:20           16 2259Z 14
05Jul2020@22:59:38 (chan) <- I SK0MMR DX de HB9JCB-#:   7018.3  RW1M           CW    16 dB  18 WPM  CQ      2259Z
05Jul2020@22:59:39 (chan) <- I SK0MMR DX de HB9JCB-#:   3516.9  RA1AFT         CW     9 dB  26 WPM  CQ      2259Z
05Jul2020@22:59:39 (chan) <- I SK0MMR DX de KO7SS-7-#:  14057.6  K7GT           CW     6 dB  21 WPM  CQ      2259Z
05Jul2020@22:59:39 (chan) <- I SK0MMR DX de K9LC-#:    28169.9  VA3XCD/B       CW     9 dB  10 WPM  BEACON  2259Z
05Jul2020@22:59:40 (chan) <- I SK0MMR DX de HB9DCO-#:   7018.2  RW1M           CW    25 dB  18 WPM  CQ      2259Z
05Jul2020@22:59:40 (chan) <- I SK0MMR DX de EA5WU-#:    7018.3  RW1M           CW    19 dB  18 WPM  CQ      2259Z

* As you can see, there are frequently more than one spotter for a
  callsign:

* I normalise the frequency and cache up to 9 copies from different
  spots. In order to do this I have to wait a few (comfigurable) seconds
  for the client to collect a reasonable number of copies. More copies 
  may come in after 9 copies have been received. Once I have enough 
  copies to be sure that the callsign is at least agreeed upon by more
  than one skimmer, or the wait timer goes off, I emit a spot.  By this
  means I can reduce the number of spots sent to a node user by up to a
  factor of 10 for CW etc spots and about 8 for FTx spots.

  For example, from the trace above, all the RW1M RBN spots become just
  one line:

DX de F8DGY-#:     7018.3 RW1M         CW  23dB Q:9* Z:20           16 2259Z 14

* No RBN spots can leak out of the node to the general cluster. Each
  node that wants to use the RBN *must* establish their own
  connections to the RBN.

* Currently no RBN spots are stored. This may well change but how and
  where these spots are stored is not yet decided. Only "DXSpider
  curated" spots (like the example above) will be stored (if/when they
  are). Sh/dx will be suitably modified if storage happens. 

* There are some things that need to be explained:

a) The input format from the RBN is not the same as format emitted by
the cluster node. This is part of the unhelpfulness to mixing a raw
RBN feed with normal spots.

b) Each spot sent out to a node user has a "Qwalitee" marker, In this
case Q:9*. The '9' means that I have received 9 copies of this spot
from different skimmers and, in this case, they did not agree on the
frequency (7018.2 - 7018.4) which is indicated by a '*'. The frequency
shown is the majority decision. If this station has been active for
some time and he is still calling CQ after some time (configurable,
but currently 60 minutes) and gaps for QSOs or tea breaks are ignored,
then a '+' character will be added.

If the "Qualitee" Q:1 is seen on a CW spot, then only one skimmer has
seen that spot and the callsign *could* be wrong, but frequently, if
it is wrong, it is more obvious than the example below. But if Q is
Q:2 and above, then the callsign is much more likely to be correct.

DX de DJ9IE-#:    14034.9 UN7BBD       CW   4dB Q:5*+              17 1444Z 14
DX de OL7M-#:     14037.9 UA6LQ        CW  13dB Q:7                16 1448Z 15
DX de LZ3CB-#:    28050.2 DL4HRM       CW   7dB Q:1                14 1448Z 20

c) I ditch the WPM and the 'CQ' as not being hugely relevant. 

d) If there is a Z:nn[,mm...] is there it means that this call was also heard
in CQ Zone 20. There can a ',' separated list of as many zones as
there the space available (and this spot call was heard by :-). You
will notice the spot zone and skimmer call zone around the time. This
can be activated with a 'set/dxcq' command. This is completely
optional.

DX de LZ4UX-#:    14015.5 ON7TQ        CW   6dB Q:9 Z:5,14,15,40   14 0646Z 20
DX de VE7CC-#:     3573.0 N8ADO        FT8 -14dB Q:4 Z:4,5          4 0647Z  3
DX de DM7EE-#:    14027.5 R1AC         CW   9dB Q:9* Z:5,15,17,20  16 0643Z 14
DX de WE9V-#:      7074.0 EA7ALL       FT8 -9dB Q:2+ Z:5           14 0641Z  4

e) I shorten the skimmer callsign to 6 characters - having first
chopped off any SSIDs, spurious /xxx strings from the end leaving just
the base callsign, before (re-)adding '-#' on the end. This is done to
minimise the movement rightwards as in the incoming spot from
KO7SS-7-# below. There are some very strange skimmer callsigns with
all sorts of spurious endings, all of which I attempt to reduce to the
base callsign. Some skimmer base callsigns still might be shortened
for display purposes. Things like '3V/K5WEM' won't fit in six
characters but the whole base callsign is used for zone info,
internally, but only the first 6 characters are displayed in any
spot. See KO7SS-7-# below:

05Jul2020@22:59:39 (chan) <- I SK0MMR DX de HB9JCB-#:   3516.9  RA1AFT         CW     9 dB  26 WPM  CQ      2259Z
05Jul2020@22:59:39 (chan) <- I SK0MMR DX de KO7SS-7-#:  14057.6  K7GT           CW     6 dB  21 WPM  CQ      2259Z
05Jul2020@22:59:39 (chan) <- I SK0MMR DX de K9LC-#:    28169.9  VA3XCD/B       CW     9 dB  10 WPM  BEACON  2259Z

f) I have a filter set (accept/spot by_zone 14 and not zone 14 or zone
14 and not by_zone 14) which will give me the first spot that either
spot or skimmer is in zone 14 but the other isn't. For those of us
that are bad at zones (like me) sh/dxcq is your friend. You can have
separate filters just for RBN spots if you want something different to
your spot filters. Use acc/rbn or rej/rbn. NB: these will completely
override your spot filters for RBN spots. Obviously "real" spots will
will continue to use the spot filter(s).

g) If there is NO filter in operation, then the skimmer spot with the
LOWEST signal strength will be shown. This implies that if any extra
zone are shown then the signal will be higher.

h) A filter can further drastically reduce the output sent to the
user. As this STATS line shows:

23:22:45 (*) RBN:STATS hour SK0MMR raw: 5826 sent: 555 delivered: 70 users: 1

For this hour, I received 5826 raw spots from the CW etc RBN, which
produced 555 possible spots, which my filter reduced to 70 that were
actually delivered to G1TST. For the FTx RBN, I don't have a filter
active and so I got all the possibles:

23:22:45 (*) RBN:STATS hour SK1MMR raw: 13354 sent: 1745 delivered: 1745 users: 1

---------------------------------------------------------------------

So how do you go about using this:

First you need to create an RBN user. Now you can use any call you
like and it won't be visible outside of the node. I call mine SK0MMR
and SK1MMR.

set/rbn sk0mmr sk1mmr

Now create connect scripts in /spider/connect/sk0mmr (and similarly
sk1mmr). They look like this:

/spider/connect/sk0mmr:

connect telnet telnet.reversebeacon.net 7000
'call:' '<node callsign here'

/spider/connect/sk1mmr:

connect telnet telnet.reversebeacon.net 7001
'call:' '<node callsign here'

RBN port 7000 is the "traditional" port for anything except FT4 or FT8
spots. They come from RBN port 7001.

Now put them in your local crontab in /spider/local_cmd/crontab:

* * * * * start_connect('sk0mmr') unless connected('sk0mmr')
* * * * * start_connect('sk1mmr') unless connected('sk1mmr')

This will check once every minute to see if each RBN connection is
active, you can check with the 'links' command:

                                                 Ave  Obs  Ping  Next      Filters
  Callsign Type Started                 Uptime    RTT Count Int.  Ping Iso? In  Out PC92? Address
    GB7DJK DXSP  5-Jul-2020 1722Z     7h 6m 8s   0.02   2    300    89               Y    163.172.11.79
    SK0MMR RBN   5-Jul-2020 1722Z     7h 6m 8s                 0     0                    198.137.202.75
    SK1MMR RBN   5-Jul-2020 1722Z     7h 6m 8s                 0     0                    198.137.202.75

The connections are sometimes dropped or become stuck, I have a
mechanism to detect this and it will disconnect that connection and
the normal reconnection will happen just as any other (normal) node.

It is put in the crontab, rather than started immediately, to prevent
race conditions (or just slow them down to one disconnection a
minute).

The first time a connection is made, after node startup, there is a 5
minute pause before RBN spots come out for users. This is done to fill
up (or "train") the cache. Otherwise the users will be overwhelmed by
spots - it slows down reasonably quickly - but experiment shows that 5
minutes is a reasonable compromise. The delay is configurable,
globally, for all RBN connections, but in future is likely to be
configurable per connection. Basically, because the FTx RBN data is
much more bursty and there is more of it (except on CW contests), it
could do with a somewhat longer training period.

If a connection drops and reconnects. There is no delay or extra
training time.

For users. At the moment. There is a single command that sets or
unsets ALL RBN spot sorts:

set/wantrbn
unset/wantrbn

Very soon this will be replaced with a '(un)set/skimmer' command that
allow the user to choose which categories they want. Filtering can be
used in conjunction with this proposed command to further refine
output.

This still very much "work in progress" and will be subject to
change. But I am grateful to the feedback I have received, so far,
from:

Kin EA3CV
Andy G4PIQ
Mike G8TIC
Lee VE7CC

But if you have comments, suggestions and brickbats please email me or
the support list.

Dirk G1TLH

