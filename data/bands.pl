# 
# this is the file which defines all the bands that are allowed in the system
#
# each entry can contain an arbitrary no of entries. 
#
# an entry can have an arbitrary no of PAIRS of frequencies, 
# these pairs attach themselves to the labels you provide, they are
# independant of any other pair, they can overlap, cross etc. 
#
# There MUST be at last a 'band' entry
#
# It is up to YOU to make sure that it makes sense!
# 

%bands = (
  '160m' => bless( { band => [ 1800, 2000 ], 
                     cw => [ 1800, 1830 ], 
                     rtty => [ 1838, 1841 ], 
                     ssb => [ 1831, 2000] 
                   }, 'Bands'),

  '80m' => bless( { band => [ 3500, 4000 ], 
                    cw => [ 3500, 3600 ], 
                    data => [ 3590, 3600 ], 
                    sstv => [ 3730, 3740 ], 
                    ssb => [ 3601, 4000 ]  
                  }, 'Bands'),

  '40m' => bless( { band => [ 7000, 7400 ], 
                    cw => [ 7000, 7050 ], 
                    cw => [ 7000, 7050 ], 
                    ssb => [ 7051, 7400 ] 
                  }, 'Bands'),

  '30m' => bless( { band => [ 10100, 10150 ], 
                    cw => [ 10000, 10140 ], 
                    data => [ 10141, 10150 ] 
                  }, 'Bands'),

  '20m' => bless( { band => [ 14000, 14350 ], 
                    cw => [ 14000, 14100 ], 
                    ssb => [ 14101, 14350 ], 
                    beacon => [ 14099, 14100 ],
                    sstv => [ 14225, 14235 ],
                    data => [ 14070, 14098, 14101, 14111 ],
                  }, 'Bands'),

  '18m' => bless( { band => [ 18068, 18168 ], 
                    cw => [ 18068, 18100 ], 
                    ssb => [ 18111, 18168 ], 
                    data => [ 18101, 18108], 
                    beacon => [ 18109, 18110] 
                  }, 'Bands'),

  '15m' => bless( { band => [ 21000, 21450 ], 
                    cw => [ 21000, 21150 ], 
                    data => [ 21100, 21120 ], 
                    ssb => [ 21151, 21450] 
                  }, 'Bands'),

  '12m' => bless( { band => [ 21000, 21450 ], 
                    cw => [ 21000, 21150 ], 
                    data => [ 21100, 21120 ], 
                    ssb => [ 21151, 21450] 
                  }, 'Bands'),


  '10m' => bless( { band => [ 28000, 29700 ], 
                    cw => [ 28000, 28198 ], 
                    data => [ 28120, 28150, 29200, 29300 ], 
                    space => [ 29200, 29300 ],
                    ssb => [ 28201, 29299, 29550, 29700] 
                  }, 'Bands'),

   '6m' => bless( { band => [50000, 52000],
                    cw => [50000, 50100],
                    ssb => [50100, 50500],
                  }, 'Bands'),

   '4m' => bless( { band => [70000, 70500],
                    cw => [70030, 70250],
                    ssb => [70030, 70250],
                  }, 'Bands'),

   '2m' => bless( { band => [144000, 148000],
                    cw => [144000, 144150],
                    ssb => [144150, 144500]
                  }, 'Bands'),

   '70cm' => bless( { band => [430000, 450000],
                      cw => [432000, 432150],
                      ssb => [432150, 432500],
                    }, 'Bands'),

   '23cm' => bless( { band => [ 1240000, 1325000],
                      cw => [1296000, 1296150],
                      ssb => [1296150, 1296800],
                    }, 'Bands'),

   '13cm' => bless( { band => [2310000, 2450000],
                      cw => [2320100, 2320150],
                      ssb => [2320150, 2320800],
                    }, 'Bands'),

   '9cm' => bless( { band => [3400000, 3475000],
                     cw => [3400000, 3402000],
                     ssb => [3400000, 3402000],
                    }, 'Bands'),

   '6cm' => bless( { band => [5650000, 5850000],
                     cw => [5668000, 5670000, 5760000, 5762000],
                     ssb => [5668000, 5670000, 5760000, 5762000],
                   }, 'Bands'),

   '3cm' => bless( { band => [10000000, 10500000],
                     cw => [10368000,10370000, 10450000, 10452000],
                     ssb => [10368000,10370000, 10450000, 10452000],
                   }, 'Bands'),

   '12mm' => bless( { band => [24000000, 24250000],
                      cw => [24048000, 24050000],
                      ssb => [24048000, 24050000],
                    }, 'Bands'),
    
   '6mm' => bless( { band => [47000000, 47200000],
                     cw => [47087000, 47089000],
                     ssb => [47087000, 47089000],
                  }, 'Bands'),
);

#
# the list of regions
#
# this list is so that users can say 'vhf/ssb' instead of '6m/ssb, 4m/sbb, 2m/ssb'
# just shortcuts really
#
# DO make sure that the label exists in %bands!
#

%regions = (
  hf => [ '160m', '80m', '40m', '30m', '20m', '17m', '15m', '12m', '10m' ],
  vhf => [ '6m', '4m', '2m', '70cm' ],
  uhf => [ '70cm', '23cm' ],
  shf => [ '23cm', '13cm', '9cm', '6cm', '3cm' ],
);  
