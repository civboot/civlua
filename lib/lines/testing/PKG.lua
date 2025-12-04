import {
  lua     = 'sys:lua',
  ds      = 'civ:lib/ds',
  lines   = 'civ:lib/lines',
  civtest = 'civ:lib/civtest',
}

pkg { name = 'lines_testing' }

P.testing = lua {
  mod = 'lines.testing',
  src = { 'testing.lua' },
  dep = {
    ds.ds,
    lines.lines,
    civtest.civtest,
  }
}
