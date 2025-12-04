summary"Tiny data structures and algorithms"
import {
  cc     = 'sys:cc',
  lua    = 'sys:lua',
  metaty = 'civ:lib/metaty',
  fmt    = 'civ:lib/fmt',
}
pkg {
  name     = 'ds',
  version  = '0.1-13',
  url      = 'git+http://github.com/civboot/civlua',
  homepage = "https://lua.civboot.org#Package_ds",
  license  = "UNLICENSE",
  doc      = 'README.cxt',
}

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
  },
  lib = P.dslib,
  dep = {
    metaty.metaty,
    fmt.fmt,
  }
}
