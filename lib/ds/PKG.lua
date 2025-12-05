local P = {}
P.summary = "Tiny data structures and algorithms for lua."
-- pkg {
--   name     = 'ds',
--   version  = '0.1-13',
--   url      = 'git+http://github.com/civboot/civlua',
--   homepage = "https://lua.civboot.org#Package_ds",
--   license  = "UNLICENSE",
--   doc      = 'README.cxt',
-- }

local cc  = import'sys:cc.luk'
local lua = import'sys:lua.luk'

P.dslib = cc {
  lib = 'ds',
  hdr = 'ds.h',
  src = 'ds.c',
}

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
  lib = 'civ:lib/ds dslib',
  dep = {
    'civ:lib/metaty metaty',
    'civ:lib/fmt fmt',
  },
}

return P
