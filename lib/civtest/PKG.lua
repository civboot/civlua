summary"Ultra simple testing library"
import {
  lua     = 'sys:lua',
  ds      = 'civ:lib/ds',
  fd      = 'civ:lib/fd',
  ix      = 'civ:lib/civix',
  lines   = 'civ:lib/lines',
}

pkg {
  name     = 'civtest',
  version  = '0.1-2',
  url      = 'git+http://github.com/civboot/civlua',
  homepage = "https://lua.civboot.org#Package_civtest",
  license  = "UNLICENSE",
  doc = 'README.cxt',
}

P.civtest = lua {
  mod = 'civtest',
  src = { 'civtest.lua' },
  dep = {
    ds.ds,
    fd.fd,
    ix.civix,
    lines.lines,
  },
}

-- P.call = luck {
--   name = 'civtest'
-- }
