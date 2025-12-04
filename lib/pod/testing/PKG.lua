import {
  lua     = 'sys:lua',
  ds      = 'civ:lib/ds',
  pod     = 'civ:lib/pod',
  civtest = 'civ:lib/civtest',
}
pkg { name = 'pod_testing' }

P.testing = lua {
  mod = 'pod.testing',
  src = { 'testing.lua' },
  dep = {
    ds.ds,
    pod.pod,
    civtest.civtest,
  }
}
