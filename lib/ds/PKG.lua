local P = {}
P.summary = "Tiny data structures and algorithms for lua."
local cc  = import'sys:cc.luk'
local lua = import'sys:lua.luk'

P.dslib = cc {
  lib = 'ds',
  hdr = 'ds.h',
  src = 'ds.c',
  tag = { builder = 'bootstrap', }
}

-- Note: tests are in lib/tests/
P.ds = lua {
  mod = 'ds',
  src = {
    'ds.lua',
    'ds/Iter.lua',
    'ds/LL.lua',
    'ds/path.lua',
    'ds/utf8.lua',
    'ds/heap.lua',
    'ds/log.lua',
    'ds/Grid.lua',
    'ds/load.lua',
    'ds/IFile.lua',
  },
  lib = 'civ:lib/ds#dslib',
  dep = {
    'civ:lib/metaty',
    'civ:lib/fmt',
  },
  tag = { builder = 'bootstrap' },
}

return P
