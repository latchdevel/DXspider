# 
# hop table construction
# 

package DXProt;

# default hopcount to use
$def_hopcount = 15;

# some variable hop counts based on message type
%hopcount = 
(
 11 => 10,
 16 => 10,
 17 => 10,
 19 => 10,
 21 => 10,
);

#
# the per node hop control thingy
#

%nodehops = 
(
 GB7DJK => {
			16 => 23,
			17 => 23,
		   },
 GB7TLH => {
			19 => 99,
			21 => 99,
			16 => 99,
			17 => 99,
		   }
);
