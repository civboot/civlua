import {
  lua     = 'sys:lua',
  ds      = 'civ:lib/metaty',
  civtest = 'civ:lib/civtest',
}
pkg { name = 'ds_testing' }

P.testing = lua{
  mod='ds.testing',
  dep = {
    ds.ds,
    civtest.civtest,
  },
}
